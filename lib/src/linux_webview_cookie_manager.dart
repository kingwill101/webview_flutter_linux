// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Linux cookie manager placeholder.
///
/// Cookie APIs are deliberately left unsupported until the WPE cookie store is
/// exposed through the native command bridge.
class LinuxWebViewCookieManager extends PlatformWebViewCookieManager {
  /// Creates a placeholder without allocating a native cookie store.
  // ignore: use_super_parameters
  LinuxWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(params);
}
