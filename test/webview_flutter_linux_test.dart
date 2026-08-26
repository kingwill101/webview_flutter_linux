// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  setUp(WebViewFlutterLinux.registerWith);

  test('registers the Linux WebView platform', () {
    expect(WebViewPlatform.instance, isA<WebViewFlutterLinux>());
  });

  test('creates all federated platform delegates', () {
    final platform = WebViewPlatform.instance!;
    final controller = platform.createPlatformWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller, isA<LinuxWebViewController>());
    expect(
      platform.createPlatformNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      ),
      isA<LinuxNavigationDelegate>(),
    );
    expect(
      platform.createPlatformCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
      isA<LinuxWebViewCookieManager>(),
    );
    expect(
      platform.createPlatformWebViewWidget(
        PlatformWebViewWidgetCreationParams(controller: controller),
      ),
      isA<LinuxWebViewWidget>(),
    );
  });

  test('tracks URL and history before a widget is attached', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/one')),
    );
    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/two')),
    );

    expect(await controller.currentUrl(), 'https://example.com/two');
    expect(await controller.canGoBack(), isTrue);
    expect(await controller.canGoForward(), isFalse);

    await controller.goBack();
    expect(await controller.currentUrl(), 'https://example.com/one');
    expect(await controller.canGoForward(), isTrue);
  });

  test('honors navigation prevention', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    await delegate.setOnNavigationRequest((_) => NavigationDecision.prevent);
    await controller.setPlatformNavigationDelegate(delegate);

    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/blocked')),
    );

    expect(await controller.currentUrl(), isNull);
  });
}
