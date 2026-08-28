// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux_example/https_fallback.dart';

void main() {
  group('httpFallbackUriForTlsFailure', () {
    test('downgrades an HTTPS origin to HTTP', () {
      expect(
        httpFallbackUriForTlsFailure(Uri.parse('https://facebook.org/')),
        Uri.parse('http://facebook.org/'),
      );
    });

    test('preserves the remainder of the URL', () {
      expect(
        httpFallbackUriForTlsFailure(
          Uri.parse('https://example.com:8443/a/b?q=one#result'),
        ),
        Uri.parse('http://example.com:8443/a/b?q=one#result'),
      );
    });

    test('rejects URLs that were not failed HTTPS navigations', () {
      expect(
        httpFallbackUriForTlsFailure(Uri.parse('http://example.com/')),
        isNull,
      );
      expect(
        httpFallbackUriForTlsFailure(Uri.parse('file:///tmp/index.html')),
        isNull,
      );
      expect(
        httpFallbackUriForTlsFailure(Uri.parse('https:path-only')),
        isNull,
      );
    });
  });
}
