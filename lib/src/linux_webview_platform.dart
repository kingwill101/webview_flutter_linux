// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'linux_webview_controller.dart';
import 'linux_webview_cookie_manager.dart';
import 'linux_webview_widget.dart';

/// WPE WebKit implementation of the `webview_flutter` platform interface.
///
/// Controllers remain lightweight until their corresponding widget is mounted.
/// Mounting creates a native WPE view and connects its rendered frames to a
/// Flutter texture.
class WebViewFlutterLinux extends WebViewPlatform {
  /// Installs [WebViewFlutterLinux] as the active platform implementation.
  ///
  /// Flutter calls this entry point through the package's federated plugin
  /// registration metadata.
  static void registerWith() {
    WebViewPlatform.instance = WebViewFlutterLinux();
  }

  /// Creates a lazily attached Linux WebView controller.
  @override
  LinuxWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => LinuxWebViewController(params);

  /// Creates storage for navigation callbacks used by a Linux controller.
  @override
  LinuxNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => LinuxNavigationDelegate(params);

  /// Creates the widget delegate that displays the native browser texture.
  @override
  LinuxWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => LinuxWebViewWidget(params);

  /// Creates the placeholder Linux cookie-manager delegate.
  @override
  LinuxWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => LinuxWebViewCookieManager(params);
}
