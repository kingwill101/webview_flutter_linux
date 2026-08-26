// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'native_frame_renderer.dart';

/// Coordinates WebView API calls with a lazily attached native WPE renderer.
///
/// Navigation requested before the widget mounts is retained and used as the
/// native view's initial URL. The current back/forward list is maintained in
/// Dart; it does not yet observe navigations initiated within page content.
class LinuxWebViewController extends PlatformWebViewController {
  /// Creates a controller without immediately allocating native resources.
  // ignore: use_super_parameters
  LinuxWebViewController(PlatformWebViewControllerCreationParams params)
    : super.implementation(params);

  final List<String> _history = <String>[];
  int _historyIndex = -1;
  String? _currentUrl;
  NativeFrameRenderer? _renderer;
  LinuxNavigationDelegate? _navigationDelegate;
  bool _waitingForFirstPaint = false;

  /// The renderer owned by the mounted WebView widget, if one is attached.
  ///
  /// This is exposed for the Linux widget implementation and is not part of the
  /// platform-independent `webview_flutter` API.
  NativeFrameRenderer? get renderer => _renderer;

  /// Returns the existing renderer or creates one for the current engine.
  ///
  /// The caller assumes ownership of the attachment and must eventually pass
  /// the returned instance to [detachRenderer].
  Future<NativeFrameRenderer> attachRenderer() async {
    final existing = _renderer;
    if (existing != null) return existing;

    final initialUrl = _currentUrl ?? 'about:blank';
    final engineHandle = await EngineContext.instance.getEngineHandle();
    final renderer = NativeFrameRenderer(
      engineHandle: engineHandle,
      initialUrl: initialUrl,
    );
    _renderer = renderer;
    if (_currentUrl != null) _notifyNavigationStarted(initialUrl);
    return renderer;
  }

  /// Disposes [renderer] when it is the controller's current attachment.
  ///
  /// A stale widget may safely attempt to detach an older renderer; identity
  /// checking prevents it from disposing a newer attachment.
  void detachRenderer(NativeFrameRenderer renderer) {
    if (!identical(renderer, _renderer)) return;
    _renderer = null;
    renderer.dispose();
  }

  /// Completes a pending synthetic navigation after its first painted frame.
  ///
  /// Native load-state events are not forwarded yet, so first paint is used as
  /// the observable completion boundary for controller-initiated navigation.
  void didPaintFrame() {
    if (!_waitingForFirstPaint) return;
    _waitingForFirstPaint = false;
    final url = _currentUrl;
    if (url == null) return;
    _navigationDelegate?.onProgress?.call(100);
    _navigationDelegate?.onPageFinished?.call(url);
  }

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    final file = File(absoluteFilePath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'The file does not exist.',
      );
    }
    await _loadUrl(Uri.file(file.absolute.path).toString());
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    final html = await rootBundle.loadString(key);
    await loadHtmlString(html);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    var document = html;
    if (baseUrl != null && baseUrl.isNotEmpty) {
      final base = '<base href="${const HtmlEscape().convert(baseUrl)}">';
      document = html.contains('<head>')
          ? html.replaceFirst('<head>', '<head>$base')
          : '$base$html';
    }
    await _loadUrl(
      Uri.dataFromString(
        document,
        mimeType: 'text/html',
        encoding: utf8,
      ).toString(),
    );
  }

  /// Loads a GET request without custom headers or a request body.
  ///
  /// Throws [ArgumentError] when the URI has no scheme and [UnsupportedError]
  /// for request shapes that the native command bridge does not yet support.
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (!params.uri.hasScheme) {
      throw ArgumentError('LoadRequestParams.uri must have a scheme.');
    }
    if (params.method != LoadRequestMethod.get ||
        params.headers.isNotEmpty ||
        (params.body?.isNotEmpty ?? false)) {
      throw UnsupportedError(
        'The initial Linux implementation supports GET requests without '
        'custom headers or a body.',
      );
    }
    await _loadUrl(params.uri.toString());
  }

  Future<void> _loadUrl(String url, {bool addToHistory = true}) async {
    final callback = _navigationDelegate?.onNavigationRequest;
    if (callback != null) {
      final decision = await callback(
        NavigationRequest(url: url, isMainFrame: true),
      );
      if (decision == NavigationDecision.prevent) return;
    }

    _currentUrl = url;
    if (addToHistory) {
      if (_historyIndex + 1 < _history.length) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(url);
      _historyIndex = _history.length - 1;
    }
    final renderer = _renderer;
    if (renderer != null) {
      _notifyNavigationStarted(url);
      renderer.navigate(url);
    }
  }

  void _notifyNavigationStarted(String url) {
    _waitingForFirstPaint = true;
    _navigationDelegate?.onUrlChange?.call(UrlChange(url: url));
    _navigationDelegate?.onPageStarted?.call(url);
    _navigationDelegate?.onProgress?.call(0);
  }

  @override
  Future<String?> currentUrl() async => _currentUrl;

  @override
  Future<bool> canGoBack() async => _historyIndex > 0;

  @override
  Future<bool> canGoForward() async =>
      _historyIndex >= 0 && _historyIndex + 1 < _history.length;

  @override
  Future<void> goBack() async {
    if (!await canGoBack()) return;
    _historyIndex -= 1;
    await _loadUrl(_history[_historyIndex], addToHistory: false);
  }

  @override
  Future<void> goForward() async {
    if (!await canGoForward()) return;
    _historyIndex += 1;
    await _loadUrl(_history[_historyIndex], addToHistory: false);
  }

  @override
  Future<void> reload() async {
    final url = _currentUrl;
    if (url != null) await _loadUrl(url, addToHistory: false);
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    if (handler is! LinuxNavigationDelegate) {
      throw ArgumentError.value(
        handler,
        'handler',
        'Expected a LinuxNavigationDelegate.',
      );
    }
    _navigationDelegate = handler;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    if (javaScriptMode == JavaScriptMode.disabled) {
      throw UnsupportedError(
        'Disabling JavaScript is not implemented by webview_flutter_linux.',
      );
    }
  }
}
