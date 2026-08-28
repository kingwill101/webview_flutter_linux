// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Returns the HTTP URL a browser can offer after an HTTPS connection fails.
///
/// This does not relax certificate validation. The failed HTTPS navigation
/// must be cancelled before the returned URL is loaded as a separate request,
/// and a browser UI should ask for the user's permission before doing so.
Uri? httpFallbackUriForTlsFailure(Uri failedUri) {
  if (failedUri.scheme.toLowerCase() != 'https' || failedUri.host.isEmpty) {
    return null;
  }

  return failedUri.replace(scheme: 'http');
}
