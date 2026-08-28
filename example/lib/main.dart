// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

import 'debug_display_metrics_probe.dart';
import 'debug_text_zoom_probe.dart';

void main() {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (kDebugMode && !isFlutterTest) {
    MarionetteBinding.ensureInitialized();
    _registerWebViewTextInputProbe();
    _registerWebViewPointerProbe();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const WebViewExampleApp());
}

/// Registers raw debug pointer injection for WebView input smoke tests.
///
/// Marionette's standard tap gesture uses a touchscreen contact. That is the
/// correct default for Flutter applications, but it cannot exercise browser
/// behavior that exists only for a mouse or trackpad, such as hover cursors,
/// secondary buttons, double-click press counts, wheel direction, and pan/zoom
/// streams. These events enter Flutter's normal hit-test pipeline and are
/// absent from profile and release applications.
void _registerWebViewPointerProbe() {
  registerExtension('ext.flutter.webviewPointer', (method, parameters) async {
    final action = parameters['action'];
    final x = double.tryParse(parameters['x'] ?? '');
    final y = double.tryParse(parameters['y'] ?? '');
    final button = int.tryParse(parameters['button'] ?? '') ?? 1;
    final milliseconds = int.tryParse(parameters['timeStampMs'] ?? '') ?? 0;
    final deltaX = double.tryParse(parameters['deltaX'] ?? '') ?? 0;
    final deltaY = double.tryParse(parameters['deltaY'] ?? '') ?? 0;
    final panX = double.tryParse(parameters['panX'] ?? '') ?? 0;
    final panY = double.tryParse(parameters['panY'] ?? '') ?? 0;
    final scale = double.tryParse(parameters['scale'] ?? '') ?? 1;
    final rotation = double.tryParse(parameters['rotation'] ?? '') ?? 0;
    if (x == null || y == null || button < 1 || button > 5) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams,
        'Expected numeric x/y and a button from 1 through 5.',
      );
    }
    final position = Offset(x, y);
    final timeStamp = Duration(milliseconds: milliseconds);
    final buttons = nthMouseButton(button);
    final event = switch (action) {
      'move' => PointerHoverEvent(
        timeStamp: timeStamp,
        pointer: 9001,
        device: 9001,
        position: position,
        kind: PointerDeviceKind.mouse,
      ),
      'down' => PointerDownEvent(
        timeStamp: timeStamp,
        pointer: 9001,
        device: 9001,
        position: position,
        buttons: buttons,
        kind: PointerDeviceKind.mouse,
      ),
      'up' => PointerUpEvent(
        timeStamp: timeStamp,
        pointer: 9001,
        device: 9001,
        position: position,
        buttons: 0,
        kind: PointerDeviceKind.mouse,
      ),
      'wheel' => PointerScrollEvent(
        timeStamp: timeStamp,
        device: 9001,
        position: position,
        kind: PointerDeviceKind.mouse,
        scrollDelta: Offset(deltaX, deltaY),
      ),
      'panStart' => PointerPanZoomStartEvent(
        timeStamp: timeStamp,
        pointer: 9002,
        device: 9002,
        position: position,
      ),
      'panUpdate' => PointerPanZoomUpdateEvent(
        timeStamp: timeStamp,
        pointer: 9002,
        device: 9002,
        position: position,
        pan: Offset(panX, panY),
        panDelta: Offset(deltaX, deltaY),
        scale: scale,
        rotation: rotation,
      ),
      'panEnd' => PointerPanZoomEndEvent(
        timeStamp: timeStamp,
        pointer: 9002,
        device: 9002,
        position: position,
      ),
      _ => null,
    };
    if (event == null) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams,
        'Expected action move, down, up, wheel, panStart, panUpdate, or panEnd.',
      );
    }
    GestureBinding.instance.handlePointerEvent(event);
    return ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'dispatched': action}),
    );
  });
}

/// Registers a debug-only VM extension for exercising HTML IME composition.
///
/// Marionette's generic text helper intentionally targets `EditableText` and
/// therefore cannot address an editor rendered inside a WebView texture. This
/// probe feeds the same public [TextInput] update that the Linux embedder sends
/// after a real system input-method event. It is absent from profile/release
/// applications because [main] only calls it when [kDebugMode] is true.
void _registerWebViewTextInputProbe() {
  registerExtension('ext.flutter.webviewTextInput', (method, parameters) async {
    final text = parameters['text'] ?? '';
    final selectionBase = int.tryParse(parameters['selectionBase'] ?? '');
    final selectionExtent = int.tryParse(parameters['selectionExtent'] ?? '');
    final composingBase = int.tryParse(parameters['composingBase'] ?? '');
    final composingExtent = int.tryParse(parameters['composingExtent'] ?? '');
    final cursor = selectionExtent ?? selectionBase ?? text.length;
    TextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: selectionBase ?? cursor,
          extentOffset: cursor,
        ),
        composing: composingBase == null || composingExtent == null
            ? TextRange.empty
            : TextRange(start: composingBase, end: composingExtent),
      ),
    );
    return ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'updated': true}),
    );
  });
}

/// Registers debug-only control over WPE-specific browser capabilities.
///
/// The extension lets the Linux example verify native setting changes against
/// JavaScript running in the rendered page without exposing diagnostic UI in
/// release builds.
void _registerWebViewCapabilityProbe(LinuxWebViewController controller) {
  registerExtension('ext.flutter.webviewCapabilities', (
    method,
    parameters,
  ) async {
    final action = parameters['action'];
    final enabled = switch (parameters['enabled']) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
    const booleanActions = <String>{
      'inlineMedia',
      'webRtc',
      'encryptedMedia',
      'fileAccess',
      'universalFileAccess',
      'javascriptWindows',
    };
    if (booleanActions.contains(action) && enabled == null) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams,
        'Expected enabled=true or enabled=false.',
      );
    }
    switch (action) {
      case 'inlineMedia':
        await controller.setMediaPlaybackAllowsInline(enabled!);
        break;
      case 'webRtc':
        await controller.setWebRtcEnabled(enabled!);
        break;
      case 'encryptedMedia':
        await controller.setEncryptedMediaEnabled(enabled!);
        break;
      case 'fileAccess':
        await controller.setAllowFileAccessFromFileUrls(enabled!);
        break;
      case 'universalFileAccess':
        await controller.setAllowUniversalAccessFromFileUrls(enabled!);
        break;
      case 'javascriptWindows':
        await controller.setJavaScriptCanOpenWindowsAutomatically(enabled!);
        break;
      case 'openWindow':
        final opened = await controller.runJavaScriptReturningResult(r'''
          (() => {
            window.__flutterParityPopup = window.open('about:blank', '_blank');
            if (window.__flutterParityPopup) {
              window.__flutterParityPopup.document.write(
                '<h1 id="automatic-popup">Automatic WPE popup</h1>'
              );
            }
            return window.__flutterParityPopup !== null;
          })()
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'opened': opened}),
        );
      case 'scheduleWindow':
        await controller.runJavaScript(r'''
          window.__flutterAutomaticWindowResult = 'pending';
          setTimeout(() => {
            window.__flutterParityPopup = window.open('about:blank', '_blank');
            if (window.__flutterParityPopup) {
              window.__flutterParityPopup.document.write(
                '<h1 id="automatic-popup">Automatic WPE popup</h1>'
              );
            }
            window.__flutterAutomaticWindowResult =
              window.__flutterParityPopup !== null;
          }, 250);
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'scheduled': true}),
        );
      case 'loadWindowDocument':
        await controller.loadHtmlString(r'''<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html { background: #17222b; color: #eff8ff; font-family: sans-serif; }
  body { padding: 32px; }
</style>
<h1>Automatic window probe</h1>
<p id="result">pending</p>
<script>
  window.__flutterAutomaticWindowResult = 'pending';
  setTimeout(() => {
    window.__flutterParityPopup = window.open('about:blank', '_blank');
    if (window.__flutterParityPopup) {
      window.__flutterParityPopup.document.write(
        '<h1 id="automatic-popup">Automatic WPE popup</h1>'
      );
    }
    window.__flutterAutomaticWindowResult =
      window.__flutterParityPopup !== null;
    document.querySelector('#result').textContent =
      `window.open returned ${window.__flutterAutomaticWindowResult}`;
  }, 250);
</script>''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'loaded': true}),
        );
      case 'windowResult':
        final result = await controller.runJavaScriptReturningResult(
          'window.__flutterAutomaticWindowResult ?? null',
        );
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'opened': result}),
        );
      case 'closeWindow':
        await controller.runJavaScript(
          'window.__flutterParityPopup?.close(); '
          'window.__flutterParityPopup = null;',
        );
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'closed': true}),
        );
      case 'probe':
        final result = await controller.runJavaScriptReturningResult(
          'JSON.stringify({'
          'webRtc: typeof RTCPeerConnection !== "undefined",'
          'encryptedMedia: typeof navigator.requestMediaKeySystemAccess '
          '!== "undefined"'
          '})',
        );
        final state = await controller.getCapabilityState();
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'javascript': result,
            'native': <String, bool>{
              'inlineMedia': state.inlineMediaPlaybackEnabled,
              'webRtcSetting': state.webRtcSettingEnabled,
              'webRtcSupported': state.webRtcSupportedByHost,
              'encryptedMediaSetting': state.encryptedMediaSettingEnabled,
              'encryptedMediaSupported': state.encryptedMediaSupportedByHost,
              'fileAccess': state.fileAccessFromFileUrlsEnabled,
              'universalFileAccess': state.universalAccessFromFileUrlsEnabled,
              'javascriptWindows':
                  controller.javaScriptCanOpenWindowsAutomatically,
            },
          }),
        );
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Unknown capability action.',
        );
    }
    return ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'updated': action, 'enabled': enabled}),
    );
  });
}

/// Registers debug-only control and inspection of WPE's shared cookie policy.
///
/// This deliberately uses the package's public Linux cookie-manager API. The
/// runtime probe can therefore verify the Dart contract, native async result
/// queue, and WPE network process together rather than calling test-only FFI.
void _registerWebViewCookiePolicyProbe(
  LinuxWebViewCookieManager manager,
  LinuxWebViewController controller,
) {
  registerExtension('ext.flutter.webviewCookiePolicy', (
    method,
    parameters,
  ) async {
    final action = parameters['action'];
    final enabled = switch (parameters['enabled']) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
    switch (action) {
      case 'setPolicy':
        final policy = switch (parameters['policy']) {
          'always' => LinuxCookieAcceptPolicy.always,
          'never' => LinuxCookieAcceptPolicy.never,
          'noThirdParty' => LinuxCookieAcceptPolicy.noThirdParty,
          _ => null,
        };
        if (policy == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'Expected policy=always, never, or noThirdParty.',
          );
        }
        await manager.setCookieAcceptPolicy(policy);
        break;
      case 'setThirdParty':
        if (enabled == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'Expected enabled=true or enabled=false.',
          );
        }
        await manager.setAcceptThirdPartyCookies(enabled);
        break;
      case 'setItp':
        if (enabled == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'Expected enabled=true or enabled=false.',
          );
        }
        await manager.setIntelligentTrackingPreventionEnabled(enabled);
        break;
      case 'probe':
        break;
      case 'inspectPage':
        final page = await controller.runJavaScriptReturningResult(r'''
          (() => JSON.stringify({
            url: location.href,
            result: document.getElementById('result')?.textContent ?? null,
            cookie: document.cookie,
          }))()
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'page': page}),
        );
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Expected action setPolicy, setThirdParty, setItp, probe, or '
          'inspectPage.',
        );
    }
    final policy = await manager.getCookieAcceptPolicy();
    final itp = await manager.isIntelligentTrackingPreventionEnabled();
    return ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{
        'policy': policy.name,
        'nativeValue': policy.nativeValue,
        'itpEnabled': itp,
      }),
    );
  });
}

/// Exposes the most recent federated navigation error in debug builds.
///
/// Runtime probes use this alongside the visible error label to distinguish a
/// subordinate resource failure from a successful main-document load.
void _registerWebViewNavigationErrorProbe(String? Function() currentError) {
  registerExtension('ext.flutter.webviewNavigationError', (
    method,
    parameters,
  ) async {
    return ServiceExtensionResponse.result(
      jsonEncode(<String, Object?>{'error': currentError()}),
    );
  });
}

/// Registers a debug-only rich clipboard round-trip harness.
///
/// DOM selection and inspection are prepared through JavaScript, while the
/// actual copy and paste commands still arrive as ordinary keyboard events.
/// That distinction makes the probe exercise WebKit's clipboard path and the
/// package's native desktop bridge instead of substituting test-only data.
void _registerWebViewClipboardProbe(LinuxWebViewController controller) {
  final webViewController = WebViewController.fromPlatform(controller);
  registerExtension('ext.flutter.webviewClipboard', (method, parameters) async {
    const probeHtml = r'''<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; font-family: system-ui, sans-serif; }
  body { margin: 0; padding: 32px; background: #17152a; color: #ede9ff; }
  main { display: grid; gap: 24px; max-width: 720px; margin: auto; }
  .editor { min-height: 96px; padding: 16px; border: 2px solid #7667d8;
            border-radius: 10px; background: #262044; }
  a { color: #79dfcd; }
</style>
<main>
  <h1>Rich clipboard probe</h1>
  <section>
    <h2>Copy source</h2>
    <div id="copy-source" class="editor" contenteditable="true">
      Plain prefix <strong style="color:#ff9e80">bold clipboard text</strong>
      and <a href="https://example.com/clipboard-link">a linked suffix</a>.
    </div>
  </section>
  <section>
    <h2>Paste target</h2>
    <div id="paste-target" class="editor" contenteditable="true"></div>
  </section>
</main>''';

    final action = parameters['action'];
    switch (action) {
      case 'load':
        await controller.loadHtmlString(probeHtml);
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'loaded': true}),
        );
      case 'selectSource':
        final selected = await controller.runJavaScriptReturningResult(r'''
          (() => {
            const source = document.getElementById('copy-source');
            source.focus();
            const range = document.createRange();
            range.selectNodeContents(source);
            const selection = getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            return selection.toString();
          })()
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'selected': selected}),
        );
      case 'focusTarget':
        await controller.runJavaScript(r'''
          (() => {
            const target = document.getElementById('paste-target');
            target.replaceChildren();
            target.focus();
            const range = document.createRange();
            range.selectNodeContents(target);
            range.collapse(false);
            const selection = getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
          })()
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'focused': true}),
        );
      case 'inspect':
        final result = await controller.runJavaScriptReturningResult(r'''
          (() => {
            const target = document.getElementById('paste-target');
            return JSON.stringify({
              html: target.innerHTML,
              text: target.innerText,
            });
          })()
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'result': result}),
        );
      case 'url':
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'url': await controller.currentUrl(),
            'canGoBack': await controller.canGoBack(),
            'canGoForward': await controller.canGoForward(),
          }),
        );
      case 'navigate':
        final uri = Uri.tryParse(parameters['url'] ?? '');
        if (uri == null || !uri.hasScheme) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'navigate requires an absolute url.',
          );
        }
        await webViewController.loadRequest(uri);
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'submitted': uri.toString()}),
        );
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Expected action load, selectSource, focusTarget, inspect, url, or '
          'navigate.',
        );
    }
  });
}

/// Registers a debug-only end-to-end application geolocation probe.
///
/// The probe starts from JavaScript in the visible secure page, crosses WPE's
/// permission and geolocation-manager signals, and only then publishes a fixed
/// position through the package's public Dart API. Its result is rendered into
/// the page so a successful response cannot be confused with a Dart-only unit
/// test.
void _registerWebViewGeolocationProbe(
  LinuxWebViewController controller, {
  required void Function(bool enabled) setPermissionEnabled,
}) {
  final manager = LinuxWebViewGeolocationManager.instance;
  LinuxWebViewGeolocationState? lifecycle;
  registerExtension('ext.flutter.webviewGeolocation', (
    method,
    parameters,
  ) async {
    switch (parameters['action']) {
      case 'setEnabled':
        final enabled = switch (parameters['enabled']) {
          'true' || '1' => true,
          'false' || '0' => false,
          _ => null,
        };
        if (enabled == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'setEnabled requires enabled=true or enabled=false.',
          );
        }
        await controller.setGeolocationEnabled(enabled);
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'enabled': enabled}),
        );
      case 'start':
        setPermissionEnabled(true);
        await manager.setOnGeolocationChanged((state) async {
          lifecycle = state;
          if (!state.active) return;
          await manager.updatePosition(
            const LinuxWebViewGeolocationPosition(
              latitude: 18.0179,
              longitude: -76.8099,
              accuracy: 12,
              altitude: 14,
              altitudeAccuracy: 3,
              heading: 90,
              speed: 2.5,
            ),
          );
        });
        await controller.runJavaScript(r'''
          (() => {
            let output = document.getElementById('flutter-geolocation-probe');
            if (!output) {
              output = document.createElement('div');
              output.id = 'flutter-geolocation-probe';
              Object.assign(output.style, {
                position: 'fixed', left: '20px', bottom: '20px', zIndex: 2147483647,
                padding: '12px 16px', borderRadius: '8px', color: '#10231f',
                background: '#78e0ca', font: '600 16px system-ui, sans-serif',
                boxShadow: '0 4px 18px #0006'
              });
              document.body.appendChild(output);
            }
            output.textContent = 'Geolocation: waiting for WPE';
            window.__flutterGeolocationProbe = {status: 'pending'};
            navigator.geolocation.getCurrentPosition(
              position => {
                const result = {
                  status: 'success',
                  latitude: position.coords.latitude,
                  longitude: position.coords.longitude,
                  accuracy: position.coords.accuracy,
                  altitude: position.coords.altitude,
                  altitudeAccuracy: position.coords.altitudeAccuracy,
                  heading: position.coords.heading,
                  speed: position.coords.speed
                };
                window.__flutterGeolocationProbe = result;
                output.textContent =
                  `Geolocation: ${result.latitude.toFixed(4)}, ` +
                  `${result.longitude.toFixed(4)} ±${result.accuracy}m`;
              },
              error => {
                window.__flutterGeolocationProbe = {
                  status: 'error', code: error.code, message: error.message
                };
                output.textContent = `Geolocation error ${error.code}: ${error.message}`;
              },
              {enableHighAccuracy: true, timeout: 10000}
            );
          })();
        ''');
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'started': true}),
        );
      case 'result':
        final result = await controller.runJavaScriptReturningResult(
          'JSON.stringify(window.__flutterGeolocationProbe ?? null)',
        );
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'javascript': result,
            'active': lifecycle?.active,
            'highAccuracy': lifecycle?.highAccuracy,
            'enabled': controller.geolocationEnabled,
          }),
        );
      case 'stop':
        setPermissionEnabled(false);
        lifecycle = null;
        await manager.setOnGeolocationChanged(null);
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'stopped': true}),
        );
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Expected action setEnabled, start, result, or stop.',
        );
    }
  });
}

class WebViewExampleApp extends StatelessWidget {
  const WebViewExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      showSemanticsDebugger: const bool.fromEnvironment(
        'WEBVIEW_SEMANTICS_DEBUG',
      ),
      title: 'WebView Flutter Linux',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff695de9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BrowserPage(),
    );
  }
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final TextEditingController _addressController = TextEditingController(
    text: 'https://example.com',
  );
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  late WebViewController _primaryController;
  late final WebViewController _secondaryController;
  int _progress = 0;
  String? _currentUrl;
  String? _javaScriptResult;
  String? _javaScriptChannelMessage;
  String? _navigationError;
  String? _consoleMessage;
  String? _scrollPosition;
  String? _permissionRequest;
  String? _httpAuthRequest;
  String? _sslAuthError;
  String? _webProcessStatus;
  String? _fileChooserStatus;
  String? _downloadStatus;
  LinuxWebViewPopupRequest? _popupRequest;
  WebViewController? _popupController;
  String? _popupStatus;
  String? _fullscreenStatus;
  String _startupWebsiteDataStatus = 'clear submitted before attachment';
  String _preAttachmentJavaScriptStatus = 'pending';
  bool _preAttachmentJavaScriptComplete = !kDebugMode;
  bool _recoveringWebProcess = false;
  bool _canGoBack = false;
  bool _geolocationProbeEnabled = false;
  bool _showPrimaryWebView = true;
  final List<String> _dialogCallbacks = <String>[];

  @override
  void initState() {
    super.initState();
    _primaryController =
        WebViewController(
            onPermissionRequest: (request) {
              final mayGrantGeolocation =
                  _geolocationProbeEnabled &&
                  request.types.isNotEmpty &&
                  request.types.every(
                    (type) =>
                        type == LinuxWebViewPermissionResourceType.geolocation,
                  );
              if (mounted) {
                setState(
                  () => _permissionRequest =
                      '${request.types.map((type) => type.name).join(', ')} '
                      '(${mayGrantGeolocation ? 'granted' : 'denied'} by probe)',
                );
              }
              unawaited(mayGrantGeolocation ? request.grant() : request.deny());
            },
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setVerticalScrollBarEnabled(false)
          ..setHorizontalScrollBarEnabled(false)
          ..setOverScrollMode(WebViewOverScrollMode.never)
          ..setOnConsoleMessage((message) {
            if (mounted) {
              setState(
                () => _consoleMessage =
                    '${message.level.name}: ${message.message}',
              );
            }
          })
          ..setOnScrollPositionChange((change) {
            if (mounted) {
              setState(
                () => _scrollPosition =
                    '(${change.x.round()}, ${change.y.round()})',
              );
            }
          })
          ..setOnJavaScriptAlertDialog((request) async {
            _dialogCallbacks.add('alert:${request.message}');
          })
          ..setOnJavaScriptConfirmDialog((request) async {
            _dialogCallbacks.add('confirm:${request.message}');
            return true;
          })
          ..setOnJavaScriptTextInputDialog((request) async {
            _dialogCallbacks.add(
              'prompt:${request.message}:${request.defaultText ?? ''}',
            );
            return 'Flutter response';
          })
          ..addJavaScriptChannel(
            'Probe',
            onMessageReceived: (message) {
              if (mounted) {
                setState(() => _javaScriptChannelMessage = message.message);
              }
            },
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                if (request.url.contains('iana.org')) {
                  if (mounted) {
                    setState(
                      () => _navigationError = 'Prevented: ${request.url}',
                    );
                  }
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
              onProgress: (progress) {
                if (mounted) setState(() => _progress = progress);
              },
              onPageFinished: (url) {
                if (!mounted || !_recoveringWebProcess) return;
                setState(() {
                  _recoveringWebProcess = false;
                  _webProcessStatus = 'Recovered by reloading $url';
                });
              },
              onUrlChange: (change) {
                if (!mounted) return;
                setState(() => _currentUrl = change.url);
              },
              onHttpError: (error) {
                if (!mounted) return;
                setState(
                  () => _navigationError =
                      'HTTP ${error.response?.statusCode ?? 'error'}: '
                      '${error.response?.uri ?? 'unknown resource'}',
                );
              },
              onWebResourceError: (error) {
                if (!mounted) return;
                final processTerminated =
                    error.errorType ==
                    WebResourceErrorType.webContentProcessTerminated;
                final shouldRecover =
                    processTerminated && _recoveringWebProcess;
                setState(() {
                  _navigationError =
                      '${error.isForMainFrame == false ? 'Subresource' : 'Load'} '
                      '${error.errorCode}: ${error.description}'
                      '${error.url == null ? '' : ' · ${error.url}'}';
                  if (processTerminated) {
                    _webProcessStatus =
                        'Termination reported (${error.errorCode}): '
                        '${error.description}';
                  }
                });
                if (shouldRecover) {
                  unawaited(_reloadAfterWebProcessTermination());
                }
              },
              onHttpAuthRequest: (request) {
                final isLocalProbe =
                    request.host == '127.0.0.1' &&
                    request.realm == 'webview_flutter_linux probe';
                if (isLocalProbe) {
                  request.onProceed(
                    const WebViewCredential(user: 'flutter', password: 'linux'),
                  );
                } else {
                  request.onCancel();
                }
                if (mounted) {
                  setState(
                    () => _httpAuthRequest =
                        '${request.host} · ${request.realm ?? 'no realm'} · '
                        '${isLocalProbe ? 'credentials supplied' : 'cancelled'}',
                  );
                }
              },
              onSslAuthError: (error) {
                final linuxError = error.platform is LinuxSslAuthError
                    ? error.platform as LinuxSslAuthError
                    : null;
                final uri = linuxError == null
                    ? null
                    : Uri.tryParse(linuxError.url);
                final isLocalProbe =
                    (uri?.host == '127.0.0.1' || uri?.host == 'localhost') &&
                    uri?.port == 9443;
                final decision = isLocalProbe
                    ? error.proceed()
                    : error.cancel();
                unawaited(
                  decision.catchError((Object exception, StackTrace _) {
                    if (mounted) {
                      setState(
                        () => _sslAuthError = 'resolution failed: $exception',
                      );
                    }
                  }),
                );
                if (mounted) {
                  setState(
                    () => _sslAuthError =
                        '${linuxError?.url ?? 'unknown URL'} · '
                        '${linuxError?.description ?? 'certificate failure'} · '
                        '${error.certificate?.data?.length ?? 0} DER bytes · '
                        '${isLocalProbe ? 'proceeding' : 'cancelled'}',
                  );
                }
              },
            ),
          )
          ..loadRequest(Uri.parse(_addressController.text));
    final primaryPlatform = _primaryController.platform;
    if (primaryPlatform is LinuxWebViewController) {
      if (kDebugMode) {
        _registerWebViewCapabilityProbe(primaryPlatform);
        _registerWebViewClipboardProbe(primaryPlatform);
        final cookiePlatform = _cookieManager.platform;
        if (cookiePlatform is LinuxWebViewCookieManager) {
          _registerWebViewCookiePolicyProbe(cookiePlatform, primaryPlatform);
        }
        _registerWebViewNavigationErrorProbe(() => _navigationError);
        registerWebViewDisplayMetricsProbe(primaryPlatform);
        registerWebViewTextZoomProbe(primaryPlatform);
        _registerWebViewGeolocationProbe(
          primaryPlatform,
          setPermissionEnabled: (enabled) {
            _geolocationProbeEnabled = enabled;
          },
        );
      }
      unawaited(primaryPlatform.setAllowsBackForwardNavigationGestures(true));
      unawaited(
        primaryPlatform.setOnCanGoBackChange((canGoBack) {
          if (mounted) setState(() => _canGoBack = canGoBack);
        }),
      );
      unawaited(primaryPlatform.setOnCreateWindow(_presentPopup));
      unawaited(primaryPlatform.setOnFullscreenChanged(_recordFullscreenState));
      if (kDebugMode) unawaited(_probeJavaScriptBeforeAttachment());
    }
    unawaited(_clearWebsiteDataBeforeAttachment());
    _secondaryController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadFlutterAsset('assets/secondary/index.html');
    final secondaryPlatform = _secondaryController.platform;
    if (secondaryPlatform is LinuxWebViewController) {
      unawaited(secondaryPlatform.setOnCreateWindow(_presentPopup));
      unawaited(
        secondaryPlatform.setOnFullscreenChanged(_recordFullscreenState),
      );
      unawaited(
        secondaryPlatform.setOnShowFileSelector((params) async {
          final asset = File(Platform.resolvedExecutable).absolute.parent.uri
              .resolve('data/flutter_assets/assets/secondary/upload.txt');
          if (mounted) {
            setState(
              () => _fileChooserStatus =
                  '${params.mode.name} · '
                  '${params.acceptedMimeTypes.join(', ')} · upload.txt',
            );
          }
          return <String>[asset.toFilePath()];
        }),
      );
      unawaited(
        secondaryPlatform.setOnDownloadDestination((request) async {
          final destination = File(
            '${Directory.systemTemp.path}/'
            'webview_flutter_linux_download_${request.id}.txt',
          );
          if (mounted) {
            setState(
              () => _downloadStatus =
                  'requested ${request.suggestedFilename} · '
                  '${request.contentLength ?? 'unknown'} bytes',
            );
          }
          return LinuxWebViewDownloadDestination(
            destination.path,
            allowOverwrite: true,
          );
        }),
      );
      unawaited(
        secondaryPlatform.setOnDownloadEvent((event) {
          if (!mounted) return;
          setState(
            () => _downloadStatus = switch (event.kind) {
              LinuxWebViewDownloadEventKind.createdDestination =>
                'created ${event.destination}',
              LinuxWebViewDownloadEventKind.progress =>
                '${event.receivedBytes}/${event.contentLength ?? '?'} bytes',
              LinuxWebViewDownloadEventKind.failed =>
                'failed ${event.errorCode}: '
                    '${event.errorDescription ?? 'unknown error'}',
              LinuxWebViewDownloadEventKind.finished =>
                'finished ${event.receivedBytes} bytes at '
                    '${event.destination}',
            },
          );
        }),
      );
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      unawaited(
        LinuxWebViewGeolocationManager.instance.setOnGeolocationChanged(null),
      );
    }
    _addressController.dispose();
    super.dispose();
  }

  FutureOr<bool> _presentPopup(LinuxWebViewPopupRequest request) {
    if (!mounted) return false;
    final previous = _popupRequest;
    final controller = WebViewController.fromPlatform(
      request.platformController,
    );
    unawaited(
      request.platformController.setOnFullscreenChanged(_recordFullscreenState),
    );
    setState(() {
      _popupRequest = request;
      _popupController = controller;
      _popupStatus = 'shown ${request.requestedUrl ?? 'initially blank'}';
    });
    if (previous != null && !identical(previous, request)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    unawaited(
      request.onCloseRequested.then((_) {
        if (!mounted || !identical(_popupRequest, request)) return;
        _dismissPopup('window.close requested');
      }),
    );
    return true;
  }

  void _recordFullscreenState(bool isFullscreen) {
    if (!mounted) return;
    setState(() => _fullscreenStatus = isFullscreen ? 'entered' : 'left');
  }

  void _dismissPopup(String status) {
    final request = _popupRequest;
    if (request == null) return;
    setState(() {
      _popupRequest = null;
      _popupController = null;
      _popupStatus = status;
    });
    // Let Flutter detach the popup's texture widget before applying the
    // idempotent explicit release for the case where it was never mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => request.dispose());
  }

  Future<void> _openScriptPopup() async {
    const popupHtml = '''<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; font-family: system-ui, sans-serif; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         background: #142b27; color: #d9fff6; }
  main { text-align: center; }
  button { margin: 4px; padding: 10px 16px; }
</style>
<main>
  <h1 id="script-popup-title">Independent window.open WebView</h1>
  <p>This page owns a separate Flutter texture.</p>
  <button id="fullscreen-probe" onclick="document.documentElement.requestFullscreen()">Enter fullscreen</button>
  <button id="exit-fullscreen-probe" onclick="document.exitFullscreen()">Exit fullscreen</button>
  <button id="window-close-probe" onclick="window.close()">window.close()</button>
</main>''';
    await _primaryController.runJavaScript('''
      (() => {
        const popup = window.open('', '_blank');
        if (!popup) return;
        popup.document.open();
        popup.document.write(${jsonEncode(popupHtml)});
        popup.document.close();
      })();
    ''');
  }

  Future<void> _navigate() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || !uri.hasScheme) return;
    setState(() => _navigationError = null);
    await _primaryController.loadRequest(uri);
  }

  Future<void> _clearWebsiteDataBeforeAttachment() async {
    try {
      // Both native operations are submitted synchronously while initState is
      // still running, before either WebViewWidget can attach a renderer.
      await Future.wait(<Future<void>>[
        _primaryController.clearCache(),
        _primaryController.clearLocalStorage(),
      ]);
      if (mounted) {
        setState(
          () => _startupWebsiteDataStatus =
              'cache and local storage cleared before attachment',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _startupWebsiteDataStatus = 'clear failed: $error');
      }
    }
  }

  Future<void> _probeJavaScriptBeforeAttachment() async {
    try {
      final result = await _primaryController.runJavaScriptReturningResult(
        '6 * 7',
      );
      if (!mounted) return;
      setState(() {
        _preAttachmentJavaScriptStatus = 'completed before attachment: $result';
        _preAttachmentJavaScriptComplete = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preAttachmentJavaScriptStatus = 'failed before attachment: $error';
        _preAttachmentJavaScriptComplete = true;
      });
    }
  }

  Future<void> _loadWithCustomHeaders() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || !uri.hasScheme) return;
    setState(() => _navigationError = null);
    await _primaryController.loadRequest(
      uri,
      headers: const <String, String>{
        'X-WebView-Flutter-Linux-Probe': 'custom-header-present',
      },
    );
  }

  Future<void> _postBinaryProbe() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || !uri.hasScheme) return;
    setState(() => _navigationError = null);
    await _primaryController.loadRequest(
      uri,
      method: LoadRequestMethod.post,
      headers: const <String, String>{
        'Content-Type': 'application/octet-stream',
        'X-WebView-Flutter-Linux-Probe': 'post-header-present',
      },
      body: Uint8List.fromList(<int>[
        ...utf8.encode('flutter-linux-post'),
        0,
        255,
      ]),
    );
  }

  Future<void> _readDocumentTitle() async {
    try {
      final title = await _primaryController.getTitle();
      final secondaryTitle = await _secondaryController.getTitle();
      final position = await _primaryController.getScrollPosition();
      final userAgent = await _primaryController.getUserAgent();
      await _primaryController.runJavaScript(
        'Probe.postMessage(document.title);',
      );
      await _primaryController.runJavaScript(
        "document.body.style.minHeight='2000px';"
        "window.scrollTo(0, 100);"
        "console.warn('console bridge is active');",
      );
      _dialogCallbacks.clear();
      final dialogResult = await _primaryController
          .runJavaScriptReturningResult(r'''
            (() => {
              alert('alert probe');
              const confirmed = confirm('confirm probe');
              const prompted = prompt('prompt probe', 'default probe');
              return [confirmed, prompted];
            })()
          ''');
      await _primaryController.runJavaScript(r'''
        navigator.mediaDevices?.getUserMedia({audio: true})
          .then(stream => stream.getTracks().forEach(track => track.stop()))
          .catch(() => {});
      ''');
      final presentation = await _primaryController
          .runJavaScriptReturningResult(r'''
            [
              getComputedStyle(document.documentElement).overscrollBehavior,
              getComputedStyle(
                document.documentElement,
                '::-webkit-scrollbar:vertical'
              ).width,
              getComputedStyle(
                document.documentElement,
                '::-webkit-scrollbar:horizontal'
              ).height
            ]
          ''');
      if (mounted) {
        setState(
          () => _javaScriptResult =
              '$title at (${position.dx.round()}, ${position.dy.round()}) · '
              'JS-disabled title $secondaryTitle · '
              '${userAgent ?? 'no user agent'} · dialogs $dialogResult · '
              '${_dialogCallbacks.join(', ')} · presentation $presentation',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _javaScriptResult = 'Error: $error');
    }
  }

  Future<void> _requestPageNavigation() async {
    setState(() => _navigationError = null);
    await _primaryController.runJavaScript(
      "window.location.href = 'https://www.iana.org/domains/reserved';",
    );
  }

  Future<void> _allowPageNavigation() async {
    setState(() => _navigationError = null);
    await _primaryController.runJavaScript(
      "window.location.href = 'https://example.org';",
    );
  }

  Future<void> _clearWebsiteData() async {
    try {
      const storageSentinel = '__webview_flutter_linux_clear_probe';
      const cookieName = 'webview_flutter_linux_probe';
      const cookieValue = 'round-trip';
      final cookieUrl = Uri.parse('https://example.com/');
      await _primaryController.runJavaScript(
        "localStorage.setItem('$storageSentinel', 'present');",
      );
      await _cookieManager.setCookie(
        const WebViewCookie(
          name: cookieName,
          value: cookieValue,
          domain: 'example.com',
        ),
      );
      final managerSawCookie =
          (await _cookieManager.getCookies(domain: cookieUrl)).any(
            (cookie) =>
                cookie.name == cookieName && cookie.value == cookieValue,
          );
      final pageSawCookie = await _primaryController
          .runJavaScriptReturningResult(
            "document.cookie.includes('$cookieName=$cookieValue')",
          );

      await _primaryController.clearCache();
      await _primaryController.clearLocalStorage();
      final storageWasCleared = await _primaryController
          .runJavaScriptReturningResult(
            "localStorage.getItem('$storageSentinel') === null",
          );
      final hadCookies = await _cookieManager.clearCookies();
      final cookieWasCleared = !(await _cookieManager.getCookies(
        domain: cookieUrl,
      )).any((cookie) => cookie.name == cookieName);
      final succeeded =
          managerSawCookie &&
          pageSawCookie == true &&
          storageWasCleared == true &&
          hadCookies &&
          cookieWasCleared;
      if (mounted) {
        setState(
          () => _javaScriptResult = succeeded
              ? 'Website data and cookies cleared'
              : 'Website data probe failed '
                    '(manager=$managerSawCookie, page=$pageSawCookie, '
                    'storage=$storageWasCleared, had=$hadCookies, '
                    'cleared=$cookieWasCleared)',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _javaScriptResult = 'Website data error: $error');
      }
    }
  }

  void _terminateWebProcessForTesting() {
    final platform = _primaryController.platform;
    if (platform is! LinuxWebViewController) {
      setState(() => _webProcessStatus = 'Linux controller is unavailable');
      return;
    }
    setState(() {
      _recoveringWebProcess = true;
      _webProcessStatus = 'Requesting intentional web-process termination';
    });
    try {
      // The example doubles as the live recovery harness for this test hook.
      // ignore: invalid_use_of_visible_for_testing_member
      platform.terminateWebProcessForTesting();
    } catch (error) {
      setState(() {
        _recoveringWebProcess = false;
        _webProcessStatus = 'Termination request failed: $error';
      });
    }
  }

  void _replacePrimaryControllerForTesting() {
    final replacement = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Probe',
        onMessageReceived: (message) {
          if (mounted) {
            setState(() => _javaScriptChannelMessage = message.message);
          }
        },
      )
      ..setOnConsoleMessage((message) {
        if (mounted) {
          setState(
            () => _consoleMessage = '${message.level.name}: ${message.message}',
          );
        }
      })
      ..setOnScrollPositionChange((change) {
        if (mounted) {
          setState(
            () =>
                _scrollPosition = '(${change.x.round()}, ${change.y.round()})',
          );
        }
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onUrlChange: (change) {
            if (mounted) setState(() => _currentUrl = change.url);
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(
                () =>
                    _webProcessStatus = 'Replacement controller rendered $url',
              );
            }
          },
        ),
      )
      ..loadHtmlString(
        '<!doctype html><meta charset="utf-8">'
        '<title>Replacement controller</title>'
        '<style>body{font:18px sans-serif;padding:48px;background:#f4f1ff}'
        'h1{color:#362879}</style>'
        '<h1>Replacement controller</h1>'
        '<p>This document was mounted into the retained Flutter widget.</p>',
        baseUrl: 'https://replacement.example/',
      );
    setState(() {
      _primaryController = replacement;
      _progress = 0;
      _currentUrl = null;
      _navigationError = null;
      _webProcessStatus = 'Replacing the primary controller';
    });
  }

  Future<void> _reloadAfterWebProcessTermination() async {
    try {
      await _primaryController.reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recoveringWebProcess = false;
        _webProcessStatus = 'Recovery reload failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPrimarySurface =
        _preAttachmentJavaScriptComplete && _showPrimaryWebView;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView Flutter Linux'),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: _canGoBack
                      ? () => _primaryController.goBack()
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: () => _primaryController.goForward(),
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: () => _primaryController.reload(),
                  icon: const Icon(Icons.refresh),
                ),
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _navigate(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _navigate, child: const Text('Go')),
                IconButton(
                  key: const ValueKey('load-with-custom-headers'),
                  tooltip: 'Load the address with a custom HTTP header',
                  onPressed: _loadWithCustomHeaders,
                  icon: const Icon(Icons.http),
                ),
                IconButton(
                  key: const ValueKey('post-binary-request'),
                  tooltip: 'POST a binary request body to the address',
                  onPressed: _postBinaryProbe,
                  icon: const Icon(Icons.upload_file),
                ),
                IconButton(
                  key: const ValueKey('read-page-title'),
                  tooltip: 'Probe page APIs and native titles',
                  onPressed: _readDocumentTitle,
                  icon: const Icon(Icons.code),
                ),
                IconButton(
                  key: const ValueKey('request-page-navigation'),
                  tooltip: 'Request a page-initiated navigation',
                  onPressed: _requestPageNavigation,
                  icon: const Icon(Icons.open_in_browser),
                ),
                IconButton(
                  key: const ValueKey('allow-page-navigation'),
                  tooltip: 'Allow a page-initiated navigation',
                  onPressed: _allowPageNavigation,
                  icon: const Icon(Icons.check_circle_outline),
                ),
                IconButton(
                  key: const ValueKey('open-script-popup'),
                  tooltip: 'Open an independently rendered window.open view',
                  onPressed: _openScriptPopup,
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  key: const ValueKey('clear-website-data'),
                  tooltip: 'Probe and clear website data and cookies',
                  onPressed: _clearWebsiteData,
                  icon: const Icon(Icons.cleaning_services_outlined),
                ),
                if (kDebugMode)
                  IconButton(
                    key: const ValueKey('toggle-primary-webview'),
                    tooltip: _showPrimaryWebView
                        ? 'Detach primary WebView'
                        : 'Reattach primary WebView',
                    onPressed: () => setState(
                      () => _showPrimaryWebView = !_showPrimaryWebView,
                    ),
                    icon: Icon(
                      _showPrimaryWebView
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                if (kDebugMode)
                  IconButton(
                    key: const ValueKey('terminate-web-process'),
                    tooltip: 'Terminate and recover the WebKit web process',
                    onPressed: _terminateWebProcessForTesting,
                    icon: const Icon(Icons.restart_alt),
                  ),
                if (kDebugMode)
                  IconButton(
                    key: const ValueKey('replace-primary-controller'),
                    tooltip: 'Replace the controller in the retained widget',
                    onPressed: _replacePrimaryControllerForTesting,
                    icon: const Icon(Icons.swap_horiz),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Startup website data: $_startupWebsiteDataStatus',
                key: const ValueKey('startup-website-data-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pre-attachment JavaScript: '
                  '$_preAttachmentJavaScriptStatus',
                  key: const ValueKey('pre-attachment-javascript-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _currentUrl == null
                    ? 'Waiting for WebKit lifecycle events'
                    : 'Current: $_currentUrl · $_progress%',
                key: const ValueKey('navigation-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (_javaScriptResult case final result?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'JavaScript result: $result',
                  key: const ValueKey('javascript-result'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_javaScriptChannelMessage case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'JavaScript channel: $message',
                  key: const ValueKey('javascript-channel-result'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_navigationError case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  key: const ValueKey('navigation-error'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_consoleMessage case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Console: $message${_scrollPosition == null ? '' : ' · scroll $_scrollPosition'}',
                  key: const ValueKey('console-message'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_permissionRequest case final permission?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Permission request: $permission',
                  key: const ValueKey('permission-request'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_httpAuthRequest case final authentication?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'HTTP authentication: $authentication',
                  key: const ValueKey('http-authentication-request'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_sslAuthError case final sslError?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'TLS certificate error: $sslError',
                  key: const ValueKey('ssl-authentication-error'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_webProcessStatus case final processStatus?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Web process: $processStatus',
                  key: const ValueKey('web-process-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_fileChooserStatus case final chooserStatus?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'File chooser: $chooserStatus',
                  key: const ValueKey('file-chooser-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_downloadStatus case final downloadStatus?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Download: $downloadStatus',
                  key: const ValueKey('download-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_popupStatus case final popupStatus?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Popup: $popupStatus',
                  key: const ValueKey('popup-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (_fullscreenStatus case final fullscreenStatus?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Fullscreen: $fullscreenStatus',
                  key: const ValueKey('fullscreen-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: showPrimarySurface
                          ? WebViewWidget(
                              key: const ValueKey('primary-webview'),
                              controller: _primaryController,
                            )
                          : ColoredBox(
                              key: ValueKey(
                                _preAttachmentJavaScriptComplete
                                    ? 'primary-webview-detached'
                                    : 'primary-webview-pre-attachment',
                              ),
                              color: const Color(0xff10131d),
                              child: Center(
                                child: Text(
                                  _preAttachmentJavaScriptComplete
                                      ? 'Primary WebView detached; native state retained'
                                      : 'Running JavaScript before the first widget attachment',
                                ),
                              ),
                            ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: WebViewWidget(controller: _secondaryController),
                    ),
                  ],
                ),
                if (_popupController case final popupController?)
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0xdd080a11),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 820,
                            maxHeight: 560,
                          ),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                ListTile(
                                  title: const Text('Related WebView popup'),
                                  subtitle: Text(
                                    '${_popupRequest?.requestedUrl ?? 'initially blank'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    key: const ValueKey('close-popup'),
                                    tooltip: 'Close popup',
                                    onPressed: () =>
                                        _dismissPopup('closed by Flutter'),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: WebViewWidget(
                                    key: ValueKey(_popupRequest),
                                    controller: popupController,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
