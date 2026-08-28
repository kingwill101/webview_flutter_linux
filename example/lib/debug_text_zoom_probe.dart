// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:webview_flutter_linux/webview_flutter_linux.dart';

/// Registers a debug-only native text-zoom verification probe.
///
/// The document contains one text span and one fixed-size, text-free box. Its
/// measurements let a driver distinguish WPE's text-only zoom from ordinary
/// page zoom: the text bounds must change while the box remains 120 by 80 CSS
/// pixels. The extension is absent from profile and release applications.
void registerWebViewTextZoomProbe(LinuxWebViewController controller) {
  registerExtension('ext.flutter.webviewTextZoom', (method, parameters) async {
    switch (parameters['action']) {
      case 'load':
        await controller.loadHtmlString(_textZoomDocument);
        await _waitForTextZoomDocument(controller);
        return ServiceExtensionResponse.result(
          jsonEncode(await _textZoomMetrics(controller)),
        );
      case 'set':
        final percentage = int.tryParse(parameters['percentage'] ?? '');
        if (percentage == null || percentage < 10 || percentage > 1000) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'set requires percentage from 10 through 1000.',
          );
        }
        await controller.setTextZoom(percentage);
        // WPE updates layout asynchronously after changing its zoom factor.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return ServiceExtensionResponse.result(
          jsonEncode(await _textZoomMetrics(controller)),
        );
      case 'probe':
        return ServiceExtensionResponse.result(
          jsonEncode(await _textZoomMetrics(controller)),
        );
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Expected action load, set, or probe.',
        );
    }
  });
}

Future<Map<String, Object?>> _textZoomMetrics(
  LinuxWebViewController controller,
) async {
  final encoded = await controller.runJavaScriptReturningResult(r'''
    (() => {
      const text = document.getElementById('text-zoom-target');
      const box = document.getElementById('text-zoom-reference');
      const textBounds = text.getBoundingClientRect();
      const boxBounds = box.getBoundingClientRect();
      return JSON.stringify({
        text: {
          width: textBounds.width,
          height: textBounds.height,
          fontSize: getComputedStyle(text).fontSize,
          lineHeight: getComputedStyle(text).lineHeight
        },
        reference: {width: boxBounds.width, height: boxBounds.height},
        viewport: {width: innerWidth, height: innerHeight}
      });
    })()
  ''');
  if (encoded is! String) {
    throw StateError('WPE returned non-string text zoom metrics: $encoded');
  }
  return <String, Object?>{
    'percentage': controller.textZoom,
    'javascript': jsonDecode(encoded),
  };
}

Future<void> _waitForTextZoomDocument(LinuxWebViewController controller) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    try {
      final ready = await controller.runJavaScriptReturningResult(
        'document.getElementById("text-zoom-target") !== null',
      );
      if (ready == true) return;
    } on Object {
      // The loadHtmlString navigation may not have committed yet.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('The text zoom probe document did not become ready.');
}

const _textZoomDocument = r'''<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; font-family: system-ui, sans-serif; }
  body { margin: 32px; background: #151827; color: #f4f0ff; }
  #text-zoom-target {
    display: inline-block;
    font: 400 20px/1 system-ui, sans-serif;
    white-space: nowrap;
  }
  #text-zoom-reference {
    width: 120px;
    height: 80px;
    margin-top: 32px;
    background: #7668e8;
  }
</style>
<span id="text-zoom-target">Text zoom measurement</span>
<div id="text-zoom-reference" aria-label="Fixed-size reference"></div>
''';
