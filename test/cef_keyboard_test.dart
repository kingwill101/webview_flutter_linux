// SPDX-License-Identifier: UNLICENSED

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zikzak_inappwebview_latest_probe/src/cef_keyboard.dart';

void main() {
  test('maps DOM-compatible Windows key codes', () {
    expect(cefWindowsKeyCode(LogicalKeyboardKey.keyA), 0x41);
    expect(cefWindowsKeyCode(LogicalKeyboardKey.digit7), 0x37);
    expect(cefWindowsKeyCode(LogicalKeyboardKey.enter), 0x0d);
    expect(cefWindowsKeyCode(LogicalKeyboardKey.arrowLeft), 0x25);
  });

  test('combines CEF keyboard modifier flags', () {
    expect(
      cefKeyboardModifiers(
        shift: true,
        control: true,
        alt: false,
        meta: false,
        capsLock: false,
        numLock: false,
      ),
      cefEventFlagShiftDown | cefEventFlagControlDown,
    );
  });
}
