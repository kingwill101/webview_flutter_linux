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

@ffi.Native<ffi.Uint32 Function()>(symbol: 'zikzak_cef_frame_width')
external int zikzakCefFrameWidth();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'zikzak_cef_frame_height')
external int zikzakCefFrameHeight();

@ffi.Native<ffi.Size Function()>(symbol: 'zikzak_cef_frame_byte_length')
external int zikzakCefFrameByteLength();

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

@ffi.Native<ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Float)>(
  symbol: 'zikzak_cef_resize',
)
external int zikzakCefResize(
  int logicalWidth,
  int logicalHeight,
  double deviceScaleFactor,
);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>(symbol: 'zikzak_cef_set_focus')
external int zikzakCefSetFocus(int focused);

@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32)>(
  symbol: 'zikzak_cef_send_mouse_move',
)
external int zikzakCefSendMouseMove(
  int x,
  int y,
  int modifiers,
  int mouseLeave,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
  )
>(symbol: 'zikzak_cef_send_mouse_button')
external int zikzakCefSendMouseButton(
  int x,
  int y,
  int modifiers,
  int button,
  int mouseUp,
  int clickCount,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32, ffi.Int32)
>(symbol: 'zikzak_cef_send_mouse_wheel')
external int zikzakCefSendMouseWheel(
  int x,
  int y,
  int modifiers,
  int deltaX,
  int deltaY,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Uint32,
  )
>(symbol: 'zikzak_cef_send_key')
external int zikzakCefSendKey(
  int eventType,
  int modifiers,
  int windowsKeyCode,
  int nativeKeyCode,
  int character,
  int unmodifiedCharacter,
);
