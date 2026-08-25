// SPDX-License-Identifier: UNLICENSED

import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    await const RustBuilder(assetName: 'src/native_frame_bindings.dart')
        .run(input: input, output: output);
  });
}
