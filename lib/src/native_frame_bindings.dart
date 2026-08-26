// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Raw Dart FFI declarations for the versioned Rust WebView ABI.
///
/// These declarations intentionally mirror the exported Rust signatures. A
/// zero status indicates success, positive statuses are operation-specific,
/// and negative statuses indicate failure. Except for API discovery and view
/// creation, every operation is scoped by an opaque native view handle.
library;

import 'dart:ffi' as ffi;

/// Returns the version of the Rust bridge's exported ABI.
@ffi.Native<ffi.Uint32 Function()>(symbol: 'webview_flutter_linux_api_version')
external int webviewFlutterLinuxApiVersion();

/// Creates a native view for [engineHandle] and writes its handle to
/// [outputHandle].
///
/// [initialUrl] must point to a null-terminated UTF-8 string. The returned
/// handle scopes every subsequent texture and WPE operation.
@ffi.Native<
  ffi.Int32 Function(ffi.Int64, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Uint64>)
>(symbol: 'webview_flutter_linux_view_create')
external int webviewFlutterLinuxViewCreate(
  int engineHandle,
  ffi.Pointer<ffi.Char> initialUrl,
  ffi.Pointer<ffi.Uint64> outputHandle,
);

/// Releases the native view identified by [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_view_dispose',
)
external int webviewFlutterLinuxViewDispose(int handle);

/// Returns the Flutter external-texture identifier for [handle].
@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_id',
)
external int webviewFlutterLinuxTextureId(int handle);

/// Returns the latest texture width in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_width',
)
external int webviewFlutterLinuxTextureWidth(int handle);

/// Returns the latest texture height in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_height',
)
external int webviewFlutterLinuxTextureHeight(int handle);

/// Returns a counter that changes when the native texture content changes.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_generation',
)
external int webviewFlutterLinuxTextureGeneration(int handle);

/// Notifies Flutter that a new frame is available for [handle]'s texture.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_request_frame',
)
external int webviewFlutterLinuxTextureRequestFrame(int handle);

/// Returns the number of DMA-BUF frames copied into fallback storage.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_dma_buf_copy_count',
)
external int webviewFlutterLinuxTextureDmaBufCopyCount(int handle);

/// Runs pending GLib and WPE work for one non-blocking iteration.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_pump',
)
external int webviewFlutterLinuxWpePump(int handle);

/// Navigates [handle] to the null-terminated UTF-8 [url].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_navigate',
)
external int webviewFlutterLinuxWpeNavigate(
  int handle,
  ffi.Pointer<ffi.Char> url,
);

/// Resizes the native browser surface to physical [width] by [height].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_resize',
)
external int webviewFlutterLinuxWpeResize(int handle, int width, int height);

/// Updates whether [handle] receives keyboard focus.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_focus',
)
external int webviewFlutterLinuxWpeSetFocus(int handle, int focused);

/// Updates whether [handle] is visible to the application.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_visibility',
)
external int webviewFlutterLinuxWpeSetVisibility(int handle, int visible);

/// Sends a mouse movement or leave event in physical surface coordinates.
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

/// Sends a mouse-button transition in physical surface coordinates.
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

/// Sends a mouse-wheel event in physical surface coordinates.
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

/// Sends a Chromium-compatible key event to the native browser view.
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

/// Returns the native clipboard revision, or a negative value on failure.
@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_change_count',
)
external int webviewFlutterLinuxWpeClipboardChangeCount(int handle);

/// Returns the byte length of the native clipboard's UTF-8 text.
@ffi.Native<ffi.IntPtr Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_text_length',
)
external int webviewFlutterLinuxWpeClipboardTextLength(int handle);

/// Copies native clipboard bytes into [destination].
///
/// [destinationLength] must be at least the value returned by
/// [webviewFlutterLinuxWpeClipboardTextLength]. The result is the number of
/// bytes copied, or a negative status code.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_copy_text',
)
external int webviewFlutterLinuxWpeClipboardCopyText(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Replaces the native clipboard text with null-terminated UTF-8 [text].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_set_text',
)
external int webviewFlutterLinuxWpeClipboardSetText(
  int handle,
  ffi.Pointer<ffi.Char> text,
);

/// Returns a counter that changes when WPE exposes a new context menu.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_generation',
)
external int webviewFlutterLinuxWpeContextMenuGeneration(int handle);

/// Returns the context menu's horizontal physical coordinate.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_x',
)
external double webviewFlutterLinuxWpeContextMenuX(int handle);

/// Returns the context menu's vertical physical coordinate.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_y',
)
external double webviewFlutterLinuxWpeContextMenuY(int handle);

/// Returns the number of entries in the current native context menu.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_count',
)
external int webviewFlutterLinuxWpeContextMenuItemCount(int handle);

/// Returns the UTF-8 byte length of the context-menu item at [index].
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_title_length',
)
external int webviewFlutterLinuxWpeContextMenuItemTitleLength(
  int handle,
  int index,
);

/// Copies the context-menu item title at [index] into [destination].
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_context_menu_item_copy_title')
external int webviewFlutterLinuxWpeContextMenuItemCopyTitle(
  int handle,
  int index,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns a nonzero value when the context-menu item is a separator.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_is_separator',
)
external int webviewFlutterLinuxWpeContextMenuItemIsSeparator(
  int handle,
  int index,
);

/// Returns a nonzero value when the context-menu item can be activated.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_is_enabled',
)
external int webviewFlutterLinuxWpeContextMenuItemIsEnabled(
  int handle,
  int index,
);

/// Activates the native context-menu item at [index].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_activate',
)
external int webviewFlutterLinuxWpeContextMenuActivate(int handle, int index);

/// Dismisses the current native context menu without activating an item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_dismiss',
)
external int webviewFlutterLinuxWpeContextMenuDismiss(int handle);

/// Returns the number of frames WPE has painted for [handle].
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_paint_count',
)
external int webviewFlutterLinuxWpePaintCount(int handle);
