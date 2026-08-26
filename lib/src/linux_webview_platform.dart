// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'linux_webview_controller.dart';
import 'linux_webview_cookie_manager.dart';
import 'linux_webview_widget.dart';

/// WPE WebKit implementation of the `webview_flutter` platform interface.
class WebViewFlutterLinux extends WebViewPlatform {
  /// Registers this package as the Linux `webview_flutter` implementation.
  static void registerWith() {
    WebViewPlatform.instance = WebViewFlutterLinux();
  }

  @override
  LinuxWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => LinuxWebViewController(params);

  @override
  LinuxNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => LinuxNavigationDelegate(params);

  @override
  LinuxWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => LinuxWebViewWidget(params);

  @override
  LinuxWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => LinuxWebViewCookieManager(params);
}
