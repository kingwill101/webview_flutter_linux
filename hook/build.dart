// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    output.dependencies.addAll([
      input.packageRoot.resolve('rust/build.rs'),
      input.packageRoot.resolve('rust/Cargo.toml'),
      input.packageRoot.resolve('rust/Cargo.lock'),
    ]);

    final localWpeSdkDirectory = Directory.fromUri(
      input.packageRoot.resolve('third_party/wpe-sdk/usr/'),
    );

    await RustBuilder(
      assetName: 'src/native_frame_bindings.dart',
      features: const ['wpe-runtime'],
      extraCargoEnvironmentVariables: localWpeSdkDirectory.existsSync()
          ? {
              'PKG_CONFIG_PATH': Directory.fromUri(
                localWpeSdkDirectory.uri.resolve('lib/pkgconfig/'),
              ).path,
              'LIBRARY_PATH': Directory.fromUri(
                localWpeSdkDirectory.uri.resolve('lib/'),
              ).path,
            }
          : const {},
    ).run(input: input, output: output);
  });
}
