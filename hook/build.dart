// SPDX-License-Identifier: UNLICENSED

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final backendConfiguration = File.fromUri(
      input.packageRoot.resolve('tool/browser_backend'),
    );
    output.dependencies.add(backendConfiguration.uri);
    final backend = backendConfiguration.readAsStringSync().trim();
    if (backend != 'cef' && backend != 'wpe') {
      throw StateError(
        'Unsupported browser backend "$backend" in '
        '${backendConfiguration.path}; expected cef or wpe.',
      );
    }
    final cefDirectory = Directory.fromUri(
      input.packageRoot.resolve('third_party/cef/'),
    );
    final localWpeSdkDirectory = Directory.fromUri(
      input.packageRoot.resolve('third_party/wpe-sdk/usr/'),
    );
    if (backend == 'cef' && !cefDirectory.existsSync()) {
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
      features: [backend == 'wpe' ? 'wpe-runtime' : 'cef-runtime'],
      extraCargoEnvironmentVariables: switch (backend) {
        'cef' => {'CEF_PATH': cefDirectory.path},
        'wpe' when localWpeSdkDirectory.existsSync() => {
          'PKG_CONFIG_PATH': Directory.fromUri(
            localWpeSdkDirectory.uri.resolve('lib/pkgconfig/'),
          ).path,
          'LIBRARY_PATH': Directory.fromUri(
            localWpeSdkDirectory.uri.resolve('lib/'),
          ).path,
        },
        _ => const {},
      },
    ).run(input: input, output: output);

    if (backend == 'cef') {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'src/cef_runtime_asset.dart',
          linkMode: DynamicLoadingBundled(),
          file: cefDirectory.uri.resolve('libcef.so'),
        ),
      );
    }
  });
}
