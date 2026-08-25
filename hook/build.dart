// SPDX-License-Identifier: UNLICENSED

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final cefDirectory = Directory.fromUri(
      input.packageRoot.resolve('third_party/cef/'),
    );
    if (!cefDirectory.existsSync()) {
      throw StateError(
        'CEF is not installed at ${cefDirectory.path}. '
        'Run the setup command documented in README.md.',
      );
    }

    output.dependencies.addAll([
      input.packageRoot.resolve('rust/build.rs'),
      input.packageRoot.resolve('rust/Cargo.toml'),
      input.packageRoot.resolve('rust/Cargo.lock'),
    ]);

    await RustBuilder(
      assetName: 'src/native_frame_bindings.dart',
      features: const ['cef-runtime'],
      extraCargoEnvironmentVariables: {'CEF_PATH': cefDirectory.path},
    ).run(input: input, output: output);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/cef_runtime_asset.dart',
        linkMode: DynamicLoadingBundled(),
        file: cefDirectory.uri.resolve('libcef.so'),
      ),
    );
  });
}
