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
    if (_active) {
      throw StateError(
        'webview_flutter_linux currently supports one active WebViewWidget. '
        'Multiple-view support requires the handle-based native runtime.',
      );
    }
    _active = true;
    try {
      _checkStatus(
        'Flutter texture initialization',
        webviewFlutterLinuxTextureInitialize(engineHandle),
        allowAlreadyInitialized: false,
      );
      final nativeUrl = initialUrl.toNativeUtf8();
      try {
        _checkStatus(
          'WPE initialization',
          webviewFlutterLinuxWpeInitialize(nativeUrl.cast()),
          allowAlreadyInitialized: false,
        );
      } finally {
        calloc.free(nativeUrl);
      }
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount();
      setVisibility(true);
    } catch (_) {
      webviewFlutterLinuxShutdown();
      _active = false;
      rethrow;
    }
  }

  static bool _active = false;

  final int apiVersion;
  int _lastRequestedTextureGeneration = -1;
  int _lastPaintCount = 0;
  int _lastContextMenuGeneration = 0;
  int _lastClipboardChangeCount = -1;
  double _deviceScaleFactor = 1;
  bool _disposed = false;

  int get textureId => webviewFlutterLinuxTextureId();
  int get textureWidth => webviewFlutterLinuxTextureWidth();
  int get textureHeight => webviewFlutterLinuxTextureHeight();
  int get paintCount => webviewFlutterLinuxWpePaintCount();

  bool pump() {
    _ensureAlive();
    _checkStatus('WPE event pump', webviewFlutterLinuxWpePump());
    final generation = webviewFlutterLinuxTextureGeneration();
    final nextPaintCount = paintCount;
    if (generation != _lastRequestedTextureGeneration ||
        nextPaintCount != _lastPaintCount) {
      _checkStatus(
        'Flutter texture frame request',
        webviewFlutterLinuxTextureRequestFrame(),
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
        webviewFlutterLinuxWpeNavigate(nativeUrl.cast()),
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
      webviewFlutterLinuxWpeResize(physicalWidth, physicalHeight),
    );
  }

  void setFocus(bool focused) {
    _ensureAlive();
    _checkStatus('focus', webviewFlutterLinuxWpeSetFocus(focused ? 1 : 0));
  }

  void setVisibility(bool visible) {
    _ensureAlive();
    _checkStatus(
      'visibility',
      webviewFlutterLinuxWpeSetVisibility(visible ? 1 : 0),
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
        webviewFlutterLinuxWpeClipboardSetText(nativeText.cast()),
      );
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount();
    } finally {
      calloc.free(nativeText);
    }
  }

  String? takeClipboardText() {
    _ensureAlive();
    final changeCount = webviewFlutterLinuxWpeClipboardChangeCount();
    if (changeCount < 0 || changeCount == _lastClipboardChangeCount) {
      return null;
    }
    final length = webviewFlutterLinuxWpeClipboardTextLength();
    if (length < 0) return null;
    _lastClipboardChangeCount = changeCount;
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeClipboardCopyText(
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
    final generation = webviewFlutterLinuxWpeContextMenuGeneration();
    if (generation == 0 || generation == _lastContextMenuGeneration) {
      return null;
    }
    _lastContextMenuGeneration = generation;
    final itemCount = webviewFlutterLinuxWpeContextMenuItemCount();
    final items = <BrowserContextMenuItem>[];
    for (var index = 0; index < itemCount; index += 1) {
      final length = webviewFlutterLinuxWpeContextMenuItemTitleLength(index);
      var title = '';
      if (length > 0) {
        final destination = calloc<Uint8>(length);
        try {
          final copied = webviewFlutterLinuxWpeContextMenuItemCopyTitle(
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
              webviewFlutterLinuxWpeContextMenuItemIsSeparator(index) != 0,
          isEnabled: webviewFlutterLinuxWpeContextMenuItemIsEnabled(index) != 0,
        ),
      );
    }
    return NativeBrowserContextMenu(
      position: Offset(
        webviewFlutterLinuxWpeContextMenuX() / _deviceScaleFactor,
        webviewFlutterLinuxWpeContextMenuY() / _deviceScaleFactor,
      ),
      items: items,
    );
  }

  void activateContextMenuItem(int index) {
    _ensureAlive();
    _checkStatus(
      'context-menu action',
      webviewFlutterLinuxWpeContextMenuActivate(index),
    );
  }

  void dismissContextMenu() {
    if (!_disposed) webviewFlutterLinuxWpeContextMenuDismiss();
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
    webviewFlutterLinuxShutdown();
    _active = false;
  }
}
