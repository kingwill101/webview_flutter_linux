// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:webview_flutter_linux/webview_flutter_linux.dart';

const _hitTestX = 120;
const _hitTestY = 80;

/// Registers a debug-only HiDPI viewport and native hit-test probe.
///
/// The probe deliberately reads browser metrics from JavaScript and render
/// metrics from the live native texture. A test driver can then tap the visible
/// target through Flutter's real pointer path and compare its click count with
/// the logical and physical dimensions reported here.
void registerWebViewDisplayMetricsProbe(LinuxWebViewController controller) {
  registerExtension('ext.flutter.webviewDisplayMetrics', (
    method,
    parameters,
  ) async {
    switch (parameters['action']) {
      case 'load':
        await controller.loadHtmlString(_hitTestDocument);
        await _waitForProbeDocument(controller);
        // Give the example layout time to settle after the navigation. Its
        // normal resize callback must complete before a forced scale probe.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'loaded': true,
            'target': <String, int>{'x': _hitTestX, 'y': _hitTestY},
          }),
        );
      case 'probe':
        return ServiceExtensionResponse.result(
          jsonEncode(await _displayMetrics(controller)),
        );
      case 'forceScale':
        final scale = double.tryParse(parameters['scale'] ?? '');
        if (scale == null || !scale.isFinite || scale < 0.5 || scale > 4) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'forceScale requires a scale from 0.5 through 4.',
          );
        }
        final renderer = controller.renderer;
        if (renderer == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'The primary WebView has no attached native renderer.',
          );
        }
        final viewport = await _logicalViewport(controller);
        renderer.resizeSurface(
          logicalWidth: viewport.$1,
          logicalHeight: viewport.$2,
          deviceScaleFactor: scale,
        );
        await _waitForBrowserScale(controller, viewport, scale);
        return ServiceExtensionResponse.result(
          jsonEncode(await _displayMetrics(controller)),
        );
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Expected action load, probe, or forceScale.',
        );
    }
  });
}

Future<Map<String, Object?>> _displayMetrics(
  LinuxWebViewController controller,
) async {
  final renderer = controller.renderer;
  final javascript = await controller.runJavaScriptReturningResult(r'''
    JSON.stringify({
      devicePixelRatio: window.devicePixelRatio,
      innerWidth: window.innerWidth,
      innerHeight: window.innerHeight,
      visualViewportWidth: window.visualViewport?.width ?? null,
      visualViewportHeight: window.visualViewport?.height ?? null,
      screenWidth: window.screen.width,
      screenHeight: window.screen.height,
      clickCount: window.__flutterNativeClickCount ?? null
    })
  ''');
  final scale = renderer?.deviceScaleFactor;
  final textureWidth = renderer?.textureWidth;
  final textureHeight = renderer?.textureHeight;
  return <String, Object?>{
    'javascript': javascript,
    'native': <String, Object?>{
      'flutterViewScale':
          ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
      'scale': scale,
      'textureWidth': textureWidth,
      'textureHeight': textureHeight,
      'logicalTextureWidth': scale == null || textureWidth == null
          ? null
          : textureWidth / scale,
      'logicalTextureHeight': scale == null || textureHeight == null
          ? null
          : textureHeight / scale,
    },
  };
}

Future<(double, double)> _logicalViewport(
  LinuxWebViewController controller,
) async {
  final encoded = await controller.runJavaScriptReturningResult(
    'JSON.stringify({width: window.innerWidth, height: window.innerHeight})',
  );
  if (encoded is! String) {
    throw StateError('WPE returned non-string viewport metrics: $encoded');
  }
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, dynamic> ||
      decoded['width'] is! num ||
      decoded['height'] is! num) {
    throw StateError('WPE returned malformed viewport metrics: $encoded');
  }
  return (
    (decoded['width'] as num).toDouble(),
    (decoded['height'] as num).toDouble(),
  );
}

Future<void> _waitForBrowserScale(
  LinuxWebViewController controller,
  (double, double) viewport,
  double expectedScale,
) async {
  final expectedTextureWidth = (viewport.$1.ceil() * expectedScale).ceil();
  final expectedTextureHeight = (viewport.$2.ceil() * expectedScale).ceil();
  for (var attempt = 0; attempt < 50; attempt += 1) {
    final browserScale = await controller.runJavaScriptReturningResult(
      'window.devicePixelRatio',
    );
    final renderer = controller.renderer;
    final browserScaleMatches =
        browserScale is num &&
        (browserScale.toDouble() - expectedScale).abs() < 0.001;
    final rendererScaleMatches =
        renderer != null &&
        (renderer.deviceScaleFactor - expectedScale).abs() < 0.001;
    final textureMatches =
        renderer?.textureWidth == expectedTextureWidth &&
        renderer?.textureHeight == expectedTextureHeight;
    if (browserScaleMatches && rendererScaleMatches && textureMatches) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('WPE did not adopt display scale $expectedScale.');
}

Future<void> _waitForProbeDocument(LinuxWebViewController controller) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    try {
      final ready = await controller.runJavaScriptReturningResult(
        'document.getElementById("native-hit-target") !== null',
      );
      if (ready == true) return;
    } on Object {
      // A navigation submitted by loadHtmlString may not have committed yet.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('The HiDPI probe document did not become ready.');
}

const _hitTestDocument = r'''<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; font-family: system-ui, sans-serif; }
  body { margin: 0; min-height: 100vh; background: #17152a; color: #ede9ff; }
  #native-hit-target {
    position: fixed; left: 48px; top: 48px; width: 144px; height: 64px;
    border: 2px solid #a99cff; border-radius: 12px;
    background: #40376f; color: #fff; font: 700 16px system-ui, sans-serif;
  }
  #native-hit-result { position: fixed; left: 48px; top: 132px; }
</style>
<button id="native-hit-target" type="button">Native click target</button>
<output id="native-hit-result">Clicks: 0</output>
<script>
  window.__flutterNativeClickCount = 0;
  document.getElementById('native-hit-target').addEventListener('click', () => {
    window.__flutterNativeClickCount += 1;
    document.getElementById('native-hit-result').textContent =
      `Clicks: ${window.__flutterNativeClickCount}`;
  });
</script>''';
