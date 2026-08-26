// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';

const webViewKeyEventRawKeyDown = 0;
const webViewKeyEventKeyUp = 2;

const webViewEventFlagCapsLockOn = 1 << 0;
const webViewEventFlagShiftDown = 1 << 1;
const webViewEventFlagControlDown = 1 << 2;
const webViewEventFlagAltDown = 1 << 3;
const webViewEventFlagLeftMouseButton = 1 << 4;
const webViewEventFlagMiddleMouseButton = 1 << 5;
const webViewEventFlagRightMouseButton = 1 << 6;
const webViewEventFlagCommandDown = 1 << 7;
const webViewEventFlagNumLockOn = 1 << 8;

final _specialWindowsKeyCodes = <LogicalKeyboardKey, int>{
  LogicalKeyboardKey.backspace: 0x08,
  LogicalKeyboardKey.tab: 0x09,
  LogicalKeyboardKey.enter: 0x0d,
  LogicalKeyboardKey.numpadEnter: 0x0d,
  LogicalKeyboardKey.shiftLeft: 0x10,
  LogicalKeyboardKey.shiftRight: 0x10,
  LogicalKeyboardKey.controlLeft: 0x11,
  LogicalKeyboardKey.controlRight: 0x11,
  LogicalKeyboardKey.altLeft: 0x12,
  LogicalKeyboardKey.altRight: 0x12,
  LogicalKeyboardKey.capsLock: 0x14,
  LogicalKeyboardKey.escape: 0x1b,
  LogicalKeyboardKey.space: 0x20,
  LogicalKeyboardKey.pageUp: 0x21,
  LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.home: 0x24,
  LogicalKeyboardKey.arrowLeft: 0x25,
  LogicalKeyboardKey.arrowUp: 0x26,
  LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.insert: 0x2d,
  LogicalKeyboardKey.delete: 0x2e,
  LogicalKeyboardKey.metaLeft: 0x5b,
  LogicalKeyboardKey.metaRight: 0x5c,
  LogicalKeyboardKey.f1: 0x70,
  LogicalKeyboardKey.f2: 0x71,
  LogicalKeyboardKey.f3: 0x72,
  LogicalKeyboardKey.f4: 0x73,
  LogicalKeyboardKey.f5: 0x74,
  LogicalKeyboardKey.f6: 0x75,
  LogicalKeyboardKey.f7: 0x76,
  LogicalKeyboardKey.f8: 0x77,
  LogicalKeyboardKey.f9: 0x78,
  LogicalKeyboardKey.f10: 0x79,
  LogicalKeyboardKey.f11: 0x7a,
  LogicalKeyboardKey.f12: 0x7b,
  LogicalKeyboardKey.numLock: 0x90,
  LogicalKeyboardKey.scrollLock: 0x91,
};

int? webViewWindowsKeyCode(LogicalKeyboardKey key) {
  final special = _specialWindowsKeyCodes[key];
  if (special != null) return special;

  final label = key.keyLabel;
  if (label.length != 1) return null;
  final codeUnit = label.toUpperCase().codeUnitAt(0);
  if ((codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a)) {
    return codeUnit;
  }
  return label.codeUnitAt(0);
}

int webViewKeyboardModifiers({
  required bool shift,
  required bool control,
  required bool alt,
  required bool meta,
  required bool capsLock,
  required bool numLock,
}) {
  return (shift ? webViewEventFlagShiftDown : 0) |
      (control ? webViewEventFlagControlDown : 0) |
      (alt ? webViewEventFlagAltDown : 0) |
      (meta ? webViewEventFlagCommandDown : 0) |
      (capsLock ? webViewEventFlagCapsLockOn : 0) |
      (numLock ? webViewEventFlagNumLockOn : 0);
}
