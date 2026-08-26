// SPDX-License-Identifier: UNLICENSED

import 'dart:ffi' as ffi;

@ffi.Native<ffi.Uint32 Function()>(symbol: 'cef_texture_browser_api_version')
external int cefTextureBrowserApiVersion();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_browser_backend',
)
external int cefTextureBrowserBrowserBackend();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'cef_texture_browser_frame_width')
external int cefTextureBrowserFrameWidth();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'cef_texture_browser_frame_height')
external int cefTextureBrowserFrameHeight();

@ffi.Native<ffi.Size Function()>(
  symbol: 'cef_texture_browser_frame_byte_length',
)
external int cefTextureBrowserFrameByteLength();

@ffi.Native<ffi.Int32 Function(ffi.Int64)>(
  symbol: 'cef_texture_browser_flutter_texture_initialize',
)
external int cefTextureBrowserFlutterTextureInitialize(int engineHandle);

@ffi.Native<ffi.Int32 Function()>(symbol: 'cef_texture_browser_native_shutdown')
external int cefTextureBrowserNativeShutdown();

@ffi.Native<ffi.Int64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_id',
)
external int cefTextureBrowserFlutterTextureId();

@ffi.Native<ffi.Int32 Function(ffi.Uint32, ffi.Uint32)>(
  symbol: 'cef_texture_browser_flutter_texture_resize',
)
external int cefTextureBrowserFlutterTextureResize(int width, int height);

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_width',
)
external int cefTextureBrowserFlutterTextureWidth();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_height',
)
external int cefTextureBrowserFlutterTextureHeight();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_generation',
)
external int cefTextureBrowserFlutterTextureGeneration();

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_request_frame',
)
external int cefTextureBrowserFlutterTextureRequestFrame();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_gl_name',
)
external int cefTextureBrowserFlutterTextureGlName();

@ffi.Native<ffi.Size Function()>(
  symbol: 'cef_texture_browser_flutter_texture_egl_display',
)
external int cefTextureBrowserFlutterTextureEglDisplay();

@ffi.Native<ffi.Size Function()>(
  symbol: 'cef_texture_browser_flutter_texture_egl_context',
)
external int cefTextureBrowserFlutterTextureEglContext();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_dma_buf_generation',
)
external int cefTextureBrowserFlutterTextureDmaBufGeneration();

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_dma_buf_status',
)
external int cefTextureBrowserFlutterTextureDmaBufStatus();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_dma_buf_copy_count',
)
external int cefTextureBrowserFlutterTextureDmaBufCopyCount();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_dma_buf_last_copy_micros',
)
external int cefTextureBrowserFlutterTextureDmaBufLastCopyMicros();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_dma_buf_max_copy_micros',
)
external int cefTextureBrowserFlutterTextureDmaBufMaxCopyMicros();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_flutter_texture_dma_buf_fence_fallback_count',
)
external int cefTextureBrowserFlutterTextureDmaBufFenceFallbackCount();

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Uint64)>(
  symbol: 'cef_texture_browser_render_test_frame',
)
external int cefTextureBrowserRenderTestFrame(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
  int frameNumber,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>(
  symbol: 'cef_texture_browser_cef_initialize',
)
external int cefTextureBrowserCefInitialize(
  ffi.Pointer<ffi.Char> runtimeDirectory,
  ffi.Pointer<ffi.Char> initialUrl,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Uint32)
>(symbol: 'cef_texture_browser_cef_initialize_with_options')
external int cefTextureBrowserCefInitializeWithOptions(
  ffi.Pointer<ffi.Char> runtimeDirectory,
  ffi.Pointer<ffi.Char> initialUrl,
  int transport,
);

@ffi.Native<ffi.Int32 Function()>(symbol: 'cef_texture_browser_cef_pump')
external int cefTextureBrowserCefPump();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_paint_count',
)
external int cefTextureBrowserCefAcceleratedPaintCount();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_valid_paint_count',
)
external int cefTextureBrowserCefAcceleratedValidPaintCount();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_plane_count',
)
external int cefTextureBrowserCefAcceleratedPlaneCount();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_format',
)
external int cefTextureBrowserCefAcceleratedFormat();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_modifier',
)
external int cefTextureBrowserCefAcceleratedModifier();

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_coded_width',
)
external int cefTextureBrowserCefAcceleratedCodedWidth();

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_coded_height',
)
external int cefTextureBrowserCefAcceleratedCodedHeight();

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_visible_width',
)
external int cefTextureBrowserCefAcceleratedVisibleWidth();

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_visible_height',
)
external int cefTextureBrowserCefAcceleratedVisibleHeight();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_cef_accelerated_first_plane_stride',
)
external int cefTextureBrowserCefAcceleratedFirstPlaneStride();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_cef_dma_buf_generation',
)
external int cefTextureBrowserCefDmaBufGeneration();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_cef_frame_generation',
)
external int cefTextureBrowserCefFrameGeneration();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_cef_frame_width',
)
external int cefTextureBrowserCefFrameWidth();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_cef_frame_height',
)
external int cefTextureBrowserCefFrameHeight();

@ffi.Native<ffi.Size Function()>(
  symbol: 'cef_texture_browser_cef_frame_byte_length',
)
external int cefTextureBrowserCefFrameByteLength();

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'cef_texture_browser_cef_copy_latest_frame',
)
external int cefTextureBrowserCefCopyLatestFrame(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>(
  symbol: 'cef_texture_browser_cef_navigate',
)
external int cefTextureBrowserCefNavigate(ffi.Pointer<ffi.Char> url);

@ffi.Native<ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Float)>(
  symbol: 'cef_texture_browser_cef_resize',
)
external int cefTextureBrowserCefResize(
  int logicalWidth,
  int logicalHeight,
  double deviceScaleFactor,
);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'cef_texture_browser_cef_set_focus',
)
external int cefTextureBrowserCefSetFocus(int focused);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'cef_texture_browser_cef_set_visibility',
)
external int cefTextureBrowserCefSetVisibility(int visible);

@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32)>(
  symbol: 'cef_texture_browser_cef_send_mouse_move',
)
external int cefTextureBrowserCefSendMouseMove(
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
>(symbol: 'cef_texture_browser_cef_send_mouse_button')
external int cefTextureBrowserCefSendMouseButton(
  int x,
  int y,
  int modifiers,
  int button,
  int mouseUp,
  int clickCount,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32, ffi.Int32)
>(symbol: 'cef_texture_browser_cef_send_mouse_wheel')
external int cefTextureBrowserCefSendMouseWheel(
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
>(symbol: 'cef_texture_browser_cef_send_key')
external int cefTextureBrowserCefSendKey(
  int eventType,
  int modifiers,
  int windowsKeyCode,
  int nativeKeyCode,
  int character,
  int unmodifiedCharacter,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>(
  symbol: 'cef_texture_browser_wpe_initialize',
)
external int cefTextureBrowserWpeInitialize(ffi.Pointer<ffi.Char> initialUrl);

@ffi.Native<ffi.Int32 Function()>(symbol: 'cef_texture_browser_wpe_pump')
external int cefTextureBrowserWpePump();

@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'cef_texture_browser_wpe_set_focus',
)
external int cefTextureBrowserWpeSetFocus(int focused);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>(
  symbol: 'cef_texture_browser_wpe_navigate',
)
external int cefTextureBrowserWpeNavigate(ffi.Pointer<ffi.Char> url);

@ffi.Native<ffi.Int32 Function(ffi.Uint32, ffi.Uint32)>(
  symbol: 'cef_texture_browser_wpe_resize',
)
external int cefTextureBrowserWpeResize(int width, int height);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'cef_texture_browser_wpe_set_visibility',
)
external int cefTextureBrowserWpeSetVisibility(int visible);

@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32)>(
  symbol: 'cef_texture_browser_wpe_send_mouse_move',
)
external int cefTextureBrowserWpeSendMouseMove(
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
>(symbol: 'cef_texture_browser_wpe_send_mouse_button')
external int cefTextureBrowserWpeSendMouseButton(
  int x,
  int y,
  int modifiers,
  int button,
  int mouseUp,
  int clickCount,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32, ffi.Int32)
>(symbol: 'cef_texture_browser_wpe_send_mouse_wheel')
external int cefTextureBrowserWpeSendMouseWheel(
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
>(symbol: 'cef_texture_browser_wpe_send_key')
external int cefTextureBrowserWpeSendKey(
  int eventType,
  int modifiers,
  int windowsKeyCode,
  int nativeKeyCode,
  int character,
  int unmodifiedCharacter,
);

@ffi.Native<ffi.Int64 Function()>(
  symbol: 'cef_texture_browser_wpe_clipboard_change_count',
)
external int cefTextureBrowserWpeClipboardChangeCount();

@ffi.Native<ffi.IntPtr Function()>(
  symbol: 'cef_texture_browser_wpe_clipboard_text_length',
)
external int cefTextureBrowserWpeClipboardTextLength();

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'cef_texture_browser_wpe_clipboard_copy_text',
)
external int cefTextureBrowserWpeClipboardCopyText(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>(
  symbol: 'cef_texture_browser_wpe_clipboard_set_text',
)
external int cefTextureBrowserWpeClipboardSetText(ffi.Pointer<ffi.Char> text);

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_wpe_context_menu_generation',
)
external int cefTextureBrowserWpeContextMenuGeneration();

@ffi.Native<ffi.Double Function()>(
  symbol: 'cef_texture_browser_wpe_context_menu_x',
)
external double cefTextureBrowserWpeContextMenuX();

@ffi.Native<ffi.Double Function()>(
  symbol: 'cef_texture_browser_wpe_context_menu_y',
)
external double cefTextureBrowserWpeContextMenuY();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_wpe_context_menu_item_count',
)
external int cefTextureBrowserWpeContextMenuItemCount();

@ffi.Native<ffi.Size Function(ffi.Uint32)>(
  symbol: 'cef_texture_browser_wpe_context_menu_item_title_length',
)
external int cefTextureBrowserWpeContextMenuItemTitleLength(int index);

@ffi.Native<ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'cef_texture_browser_wpe_context_menu_item_copy_title',
)
external int cefTextureBrowserWpeContextMenuItemCopyTitle(
  int index,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint32)>(
  symbol: 'cef_texture_browser_wpe_context_menu_item_is_separator',
)
external int cefTextureBrowserWpeContextMenuItemIsSeparator(int index);

@ffi.Native<ffi.Int32 Function(ffi.Uint32)>(
  symbol: 'cef_texture_browser_wpe_context_menu_item_is_enabled',
)
external int cefTextureBrowserWpeContextMenuItemIsEnabled(int index);

@ffi.Native<ffi.Int32 Function(ffi.Uint32)>(
  symbol: 'cef_texture_browser_wpe_context_menu_activate',
)
external int cefTextureBrowserWpeContextMenuActivate(int index);

@ffi.Native<ffi.Int32 Function()>(
  symbol: 'cef_texture_browser_wpe_context_menu_dismiss',
)
external int cefTextureBrowserWpeContextMenuDismiss();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_wpe_frame_generation',
)
external int cefTextureBrowserWpeFrameGeneration();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_wpe_paint_count',
)
external int cefTextureBrowserWpePaintCount();

@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'cef_texture_browser_wpe_valid_paint_count',
)
external int cefTextureBrowserWpeValidPaintCount();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_wpe_plane_count',
)
external int cefTextureBrowserWpePlaneCount();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'cef_texture_browser_wpe_format')
external int cefTextureBrowserWpeFormat();

@ffi.Native<ffi.Uint64 Function()>(symbol: 'cef_texture_browser_wpe_modifier')
external int cefTextureBrowserWpeModifier();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'cef_texture_browser_wpe_width')
external int cefTextureBrowserWpeWidth();

@ffi.Native<ffi.Uint32 Function()>(symbol: 'cef_texture_browser_wpe_height')
external int cefTextureBrowserWpeHeight();

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'cef_texture_browser_wpe_first_plane_stride',
)
external int cefTextureBrowserWpeFirstPlaneStride();
