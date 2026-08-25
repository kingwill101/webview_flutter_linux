// SPDX-License-Identifier: UNLICENSED

import 'dart:ffi' as ffi;

@ffi.Native<ffi.Uint32 Function()>(symbol: 'zikzak_api_version')
external int zikzakApiVersion();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'zikzak_frame_width')
external int zikzakFrameWidth();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'zikzak_frame_height')
external int zikzakFrameHeight();

@ffi.Native<ffi.Size Function()>(symbol: 'zikzak_frame_byte_length')
external int zikzakFrameByteLength();

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Uint64)>(
  symbol: 'zikzak_render_test_frame',
)
external int zikzakRenderTestFrame(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
  int frameNumber,
);
