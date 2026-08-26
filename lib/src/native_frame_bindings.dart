// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ffi' as ffi;

@ffi.Native<ffi.Uint32 Function()>(symbol: 'webview_flutter_linux_api_version')
external int webviewFlutterLinuxApiVersion();

@ffi.Native<
  ffi.Int32 Function(ffi.Int64, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Uint64>)
>(symbol: 'webview_flutter_linux_view_create')
external int webviewFlutterLinuxViewCreate(
  int engineHandle,
  ffi.Pointer<ffi.Char> initialUrl,
  ffi.Pointer<ffi.Uint64> outputHandle,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_view_dispose',
)
external int webviewFlutterLinuxViewDispose(int handle);

@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_id',
)
external int webviewFlutterLinuxTextureId(int handle);

@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_width',
)
external int webviewFlutterLinuxTextureWidth(int handle);

@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_height',
)
external int webviewFlutterLinuxTextureHeight(int handle);

@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_generation',
)
external int webviewFlutterLinuxTextureGeneration(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_request_frame',
)
external int webviewFlutterLinuxTextureRequestFrame(int handle);

@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_dma_buf_copy_count',
)
external int webviewFlutterLinuxTextureDmaBufCopyCount(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_pump',
)
external int webviewFlutterLinuxWpePump(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_navigate',
)
external int webviewFlutterLinuxWpeNavigate(
  int handle,
  ffi.Pointer<ffi.Char> url,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_resize',
)
external int webviewFlutterLinuxWpeResize(int handle, int width, int height);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_focus',
)
external int webviewFlutterLinuxWpeSetFocus(int handle, int focused);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_visibility',
)
external int webviewFlutterLinuxWpeSetVisibility(int handle, int visible);

@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32)
>(symbol: 'webview_flutter_linux_wpe_send_mouse_move')
external int webviewFlutterLinuxWpeSendMouseMove(
  int handle,
  int x,
  int y,
  int modifiers,
  int mouseLeave,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_mouse_button')
external int webviewFlutterLinuxWpeSendMouseButton(
  int handle,
  int x,
  int y,
  int modifiers,
  int button,
  int mouseUp,
  int clickCount,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_mouse_wheel')
external int webviewFlutterLinuxWpeSendMouseWheel(
  int handle,
  int x,
  int y,
  int modifiers,
  int deltaX,
  int deltaY,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Uint32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_key')
external int webviewFlutterLinuxWpeSendKey(
  int handle,
  int eventType,
  int modifiers,
  int windowsKeyCode,
  int nativeKeyCode,
  int character,
  int unmodifiedCharacter,
);

@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_change_count',
)
external int webviewFlutterLinuxWpeClipboardChangeCount(int handle);

@ffi.Native<ffi.IntPtr Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_text_length',
)
external int webviewFlutterLinuxWpeClipboardTextLength(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_copy_text',
)
external int webviewFlutterLinuxWpeClipboardCopyText(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_set_text',
)
external int webviewFlutterLinuxWpeClipboardSetText(
  int handle,
  ffi.Pointer<ffi.Char> text,
);

@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_generation',
)
external int webviewFlutterLinuxWpeContextMenuGeneration(int handle);

@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_x',
)
external double webviewFlutterLinuxWpeContextMenuX(int handle);

@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_y',
)
external double webviewFlutterLinuxWpeContextMenuY(int handle);

@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_count',
)
external int webviewFlutterLinuxWpeContextMenuItemCount(int handle);

@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_title_length',
)
external int webviewFlutterLinuxWpeContextMenuItemTitleLength(
  int handle,
  int index,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_context_menu_item_copy_title')
external int webviewFlutterLinuxWpeContextMenuItemCopyTitle(
  int handle,
  int index,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_is_separator',
)
external int webviewFlutterLinuxWpeContextMenuItemIsSeparator(
  int handle,
  int index,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_is_enabled',
)
external int webviewFlutterLinuxWpeContextMenuItemIsEnabled(
  int handle,
  int index,
);

@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_activate',
)
external int webviewFlutterLinuxWpeContextMenuActivate(int handle, int index);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_dismiss',
)
external int webviewFlutterLinuxWpeContextMenuDismiss(int handle);

@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_paint_count',
)
external int webviewFlutterLinuxWpePaintCount(int handle);
