// SPDX-License-Identifier: UNLICENSED

import 'dart:ffi';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import 'native_frame_bindings.dart';

final class NativeFrameRenderer {
  NativeFrameRenderer()
    : apiVersion = zikzakApiVersion(),
      width = zikzakFrameWidth(),
      height = zikzakFrameHeight(),
      byteLength = zikzakFrameByteLength() {
    final expectedLength = width * height * 4;
    if (byteLength != expectedLength) {
      throw StateError(
        'Rust ABI returned $byteLength bytes for a '
        '${width}x$height RGBA frame; expected $expectedLength.',
      );
    }
    _destination = calloc<Uint8>(byteLength);
    _pixels = _destination.asTypedList(byteLength);
  }

  final int apiVersion;
  final int width;
  final int height;
  final int byteLength;

  late final Pointer<Uint8> _destination;
  late final Uint8List _pixels;
  bool _disposed = false;

  Future<ui.Image> render(int frameNumber) {
    if (_disposed) {
      throw StateError('NativeFrameRenderer has been disposed.');
    }

    final result = zikzakRenderTestFrame(_destination, byteLength, frameNumber);
    if (result != 0) {
      throw StateError('Rust frame renderer failed with status $result.');
    }

    final image = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      image.complete,
    );
    return image.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_destination);
  }
}
