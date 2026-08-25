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

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>(
  symbol: 'zikzak_cef_initialize',
)
external int zikzakCefInitialize(
  ffi.Pointer<ffi.Char> runtimeDirectory,
  ffi.Pointer<ffi.Char> initialUrl,
);

@ffi.Native<ffi.Int32 Function()>(symbol: 'zikzak_cef_pump')
external int zikzakCefPump();

@ffi.Native<ffi.Uint64 Function()>(symbol: 'zikzak_cef_frame_generation')
external int zikzakCefFrameGeneration();

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'zikzak_cef_copy_latest_frame',
)
external int zikzakCefCopyLatestFrame(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>(
  symbol: 'zikzak_cef_navigate',
)
external int zikzakCefNavigate(ffi.Pointer<ffi.Char> url);
