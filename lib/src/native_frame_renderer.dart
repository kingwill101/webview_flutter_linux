// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';

import 'native_frame_bindings.dart';

final class BrowserContextMenuItem {
  const BrowserContextMenuItem({
    required this.index,
    required this.title,
    required this.isSeparator,
    required this.isEnabled,
  });

  final int index;
  final String title;
  final bool isSeparator;
  final bool isEnabled;
}

final class NativeBrowserContextMenu {
  const NativeBrowserContextMenu({required this.position, required this.items});

  final Offset position;
  final List<BrowserContextMenuItem> items;
}

final class NativeFrameRenderer {
  NativeFrameRenderer({
    required int engineHandle,
    String initialUrl = 'about:blank',
  }) : apiVersion = webviewFlutterLinuxApiVersion() {
    var createdHandle = 0;
    final outputHandle = calloc<Uint64>();
    final nativeUrl = initialUrl.toNativeUtf8();
    try {
      _checkStatus(
        'native WebView creation',
        webviewFlutterLinuxViewCreate(
          engineHandle,
          nativeUrl.cast(),
          outputHandle,
        ),
      );
      createdHandle = outputHandle.value;
      if (createdHandle == 0) {
        throw StateError('Native WebView creation returned an invalid handle.');
      }
      handle = createdHandle;
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount(
        handle,
      );
      setVisibility(true);
    } catch (_) {
      if (createdHandle != 0) {
        webviewFlutterLinuxViewDispose(createdHandle);
      }
      rethrow;
    } finally {
      calloc.free(nativeUrl);
      calloc.free(outputHandle);
    }
  }

  final int apiVersion;
  late final int handle;
  int _lastRequestedTextureGeneration = -1;
  int _lastPaintCount = 0;
  int _lastContextMenuGeneration = 0;
  int _lastClipboardChangeCount = -1;
  double _deviceScaleFactor = 1;
  bool _disposed = false;

  int get textureId => webviewFlutterLinuxTextureId(handle);
  int get textureWidth => webviewFlutterLinuxTextureWidth(handle);
  int get textureHeight => webviewFlutterLinuxTextureHeight(handle);
  int get paintCount => webviewFlutterLinuxWpePaintCount(handle);

  bool pump() {
    _ensureAlive();
    _checkStatus('WPE event pump', webviewFlutterLinuxWpePump(handle));
    final generation = webviewFlutterLinuxTextureGeneration(handle);
    final nextPaintCount = paintCount;
    if (generation != _lastRequestedTextureGeneration ||
        nextPaintCount != _lastPaintCount) {
      _checkStatus(
        'Flutter texture frame request',
        webviewFlutterLinuxTextureRequestFrame(handle),
      );
      _lastRequestedTextureGeneration = generation;
      _lastPaintCount = nextPaintCount;
      return true;
    }
    return false;
  }

  void navigate(String url) {
    _ensureAlive();
    final nativeUrl = url.toNativeUtf8();
    try {
      _checkStatus(
        'navigation',
        webviewFlutterLinuxWpeNavigate(handle, nativeUrl.cast()),
      );
    } finally {
      calloc.free(nativeUrl);
    }
  }

  void resizeSurface({
    required double logicalWidth,
    required double logicalHeight,
    required double deviceScaleFactor,
  }) {
    _ensureAlive();
    _deviceScaleFactor = deviceScaleFactor.clamp(0.5, 4).toDouble();
    final physicalWidth = (logicalWidth * _deviceScaleFactor).ceil().clamp(
      1,
      16384,
    );
    final physicalHeight = (logicalHeight * _deviceScaleFactor).ceil().clamp(
      1,
      16384,
    );
    _checkStatus(
      'surface resize',
      webviewFlutterLinuxWpeResize(handle, physicalWidth, physicalHeight),
    );
  }

  void setFocus(bool focused) {
    _ensureAlive();
    _checkStatus(
      'focus',
      webviewFlutterLinuxWpeSetFocus(handle, focused ? 1 : 0),
    );
  }

  void setVisibility(bool visible) {
    _ensureAlive();
    _checkStatus(
      'visibility',
      webviewFlutterLinuxWpeSetVisibility(handle, visible ? 1 : 0),
    );
  }

  void sendMouseMove({
    required int x,
    required int y,
    required int modifiers,
    bool mouseLeave = false,
  }) {
    _ensureAlive();
    _checkStatus(
      'mouse move',
      webviewFlutterLinuxWpeSendMouseMove(
        handle,
        _physicalCoordinate(x),
        _physicalCoordinate(y),
        modifiers,
        mouseLeave ? 1 : 0,
      ),
    );
  }

  void sendMouseButton({
    required int x,
    required int y,
    required int modifiers,
    required int button,
    required bool mouseUp,
    int clickCount = 1,
  }) {
    _ensureAlive();
    _checkStatus(
      'mouse button',
      webviewFlutterLinuxWpeSendMouseButton(
        handle,
        _physicalCoordinate(x),
        _physicalCoordinate(y),
        modifiers,
        button,
        mouseUp ? 1 : 0,
        clickCount,
      ),
    );
  }

  void sendMouseWheel({
    required int x,
    required int y,
    required int modifiers,
    required int deltaX,
    required int deltaY,
  }) {
    _ensureAlive();
    _checkStatus(
      'mouse wheel',
      webviewFlutterLinuxWpeSendMouseWheel(
        handle,
        _physicalCoordinate(x),
        _physicalCoordinate(y),
        modifiers,
        deltaX,
        deltaY,
      ),
    );
  }

  void sendKey({
    required int eventType,
    required int modifiers,
    required int windowsKeyCode,
    required int nativeKeyCode,
    int character = 0,
    int unmodifiedCharacter = 0,
  }) {
    _ensureAlive();
    _checkStatus(
      'key',
      webviewFlutterLinuxWpeSendKey(
        handle,
        eventType,
        modifiers,
        windowsKeyCode,
        nativeKeyCode,
        character,
        unmodifiedCharacter,
      ),
    );
  }

  void setClipboardText(String text) {
    _ensureAlive();
    final nativeText = text.toNativeUtf8();
    try {
      _checkStatus(
        'clipboard write',
        webviewFlutterLinuxWpeClipboardSetText(handle, nativeText.cast()),
      );
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount(
        handle,
      );
    } finally {
      calloc.free(nativeText);
    }
  }

  String? takeClipboardText() {
    _ensureAlive();
    final changeCount = webviewFlutterLinuxWpeClipboardChangeCount(handle);
    if (changeCount < 0 || changeCount == _lastClipboardChangeCount) {
      return null;
    }
    final length = webviewFlutterLinuxWpeClipboardTextLength(handle);
    if (length < 0) return null;
    _lastClipboardChangeCount = changeCount;
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeClipboardCopyText(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError('WPE clipboard read failed with status $copied.');
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  NativeBrowserContextMenu? takeContextMenu() {
    _ensureAlive();
    final generation = webviewFlutterLinuxWpeContextMenuGeneration(handle);
    if (generation == 0 || generation == _lastContextMenuGeneration) {
      return null;
    }
    _lastContextMenuGeneration = generation;
    final itemCount = webviewFlutterLinuxWpeContextMenuItemCount(handle);
    final items = <BrowserContextMenuItem>[];
    for (var index = 0; index < itemCount; index += 1) {
      final length = webviewFlutterLinuxWpeContextMenuItemTitleLength(
        handle,
        index,
      );
      var title = '';
      if (length > 0) {
        final destination = calloc<Uint8>(length);
        try {
          final copied = webviewFlutterLinuxWpeContextMenuItemCopyTitle(
            handle,
            index,
            destination,
            length,
          );
          if (copied > 0) {
            title = utf8.decode(
              destination.asTypedList(copied),
              allowMalformed: true,
            );
          }
        } finally {
          calloc.free(destination);
        }
      }
      items.add(
        BrowserContextMenuItem(
          index: index,
          title: title.replaceAll(RegExp(r'[_&]'), ''),
          isSeparator:
              webviewFlutterLinuxWpeContextMenuItemIsSeparator(handle, index) !=
              0,
          isEnabled:
              webviewFlutterLinuxWpeContextMenuItemIsEnabled(handle, index) !=
              0,
        ),
      );
    }
    return NativeBrowserContextMenu(
      position: Offset(
        webviewFlutterLinuxWpeContextMenuX(handle) / _deviceScaleFactor,
        webviewFlutterLinuxWpeContextMenuY(handle) / _deviceScaleFactor,
      ),
      items: items,
    );
  }

  void activateContextMenuItem(int index) {
    _ensureAlive();
    _checkStatus(
      'context-menu action',
      webviewFlutterLinuxWpeContextMenuActivate(handle, index),
    );
  }

  void dismissContextMenu() {
    if (!_disposed) webviewFlutterLinuxWpeContextMenuDismiss(handle);
  }

  int _physicalCoordinate(int logicalCoordinate) =>
      (logicalCoordinate * _deviceScaleFactor).round();

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('The Linux WebView renderer has been disposed.');
    }
  }

  static void _checkStatus(
    String operation,
    int status, {
    bool allowAlreadyInitialized = true,
  }) {
    if (status == 0 || (allowAlreadyInitialized && status == 1)) return;
    throw StateError('$operation failed with status $status.');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _checkStatus(
      'native WebView disposal',
      webviewFlutterLinuxViewDispose(handle),
    );
  }
}
