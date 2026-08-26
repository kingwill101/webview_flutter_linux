// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Stores navigation callbacks used by the Linux WebView implementation.
///
/// The controller currently reports navigation requests, URL changes, page
/// starts, progress, and page completion. The remaining callbacks are retained
/// here so native WPE events can be connected without changing the public
/// platform-delegate contract.
class LinuxNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates a delegate for the supplied platform-interface parameters.
  // ignore: use_super_parameters
  LinuxNavigationDelegate(PlatformNavigationDelegateCreationParams params)
    : super.implementation(params);

  /// Invoked before a controller-initiated main-frame navigation.
  NavigationRequestCallback? onNavigationRequest;

  /// Invoked when a controller-initiated navigation starts.
  PageEventCallback? onPageStarted;

  /// Invoked after the first painted frame for a requested URL.
  PageEventCallback? onPageFinished;

  /// Receives HTTP response failures once native event forwarding supports it.
  HttpResponseErrorCallback? onHttpError;

  /// Receives the synthetic start and completion progress values.
  ProgressCallback? onProgress;

  /// Receives resource failures once native event forwarding supports it.
  WebResourceErrorCallback? onWebResourceError;

  /// Invoked when the controller changes its current URL.
  UrlChangeCallback? onUrlChange;

  /// Receives authentication challenges once the native bridge supports them.
  HttpAuthRequestCallback? onHttpAuthRequest;

  /// Receives TLS certificate failures once the native bridge supports them.
  SslAuthErrorCallback? onSslAuthError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    this.onHttpError = onHttpError;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    this.onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    this.onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {
    this.onHttpAuthRequest = onHttpAuthRequest;
  }

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {
    this.onSslAuthError = onSslAuthError;
  }
}
