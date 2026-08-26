// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Cargo-side discovery for native Linux dependencies.
//!
//! Dart's `hook/build.dart` invokes Cargo through `native_toolchain_rust` and
//! supplies `PKG_CONFIG_PATH` when the package-local development SDK is used.
//! Cargo remains responsible for recording the final linker flags. Keeping
//! discovery here means command-line Cargo builds and Flutter native-assets
//! builds enforce the same WPE WebKit version floor.

fn main() {
    // Re-run if the discovery policy changes. pkg-config itself emits the
    // environment-variable rerun directives for its search configuration.
    println!("cargo::rerun-if-changed=build.rs");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        // libepoxy supplies runtime GL/EGL dispatch against Flutter's current
        // context. WPE WebKit 2.52 is the first supported/tested API surface for
        // the headless display and DMA-BUF callbacks used by this crate.
        println!("cargo::rustc-link-lib=epoxy");
        pkg_config::Config::new()
            .atleast_version("2.52")
            .probe("wpe-webkit-2.0")
            .expect("webview_flutter_linux requires the WPE WebKit 2.52 development package");
    }
}
