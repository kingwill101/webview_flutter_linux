// SPDX-License-Identifier: UNLICENSED

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import 'native_frame_bindings.dart';

final class NativeFrameRenderer {
  NativeFrameRenderer({
    bool enableCef = true,
    String initialUrl = 'https://example.com',
  }) : apiVersion = zikzakApiVersion(),
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

    if (enableCef) {
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      final runtimeDirectory = Directory(
        '${executableDirectory.path}${Platform.pathSeparator}lib',
      );
      final reusedRuntime = _initializeCef(runtimeDirectory.path, initialUrl);
      cefEnabled = true;
      if (reusedRuntime) {
        navigate(initialUrl);
      }
    }
  }

  final int apiVersion;
  final int width;
  final int height;
  final int byteLength;

  late final Pointer<Uint8> _destination;
  late final Uint8List _pixels;
  bool cefEnabled = false;
  bool cefFrameReady = false;
  int cefFrameGeneration = 0;
  bool _disposed = false;

  Future<ui.Image?> render(int frameNumber) {
    if (_disposed) {
      throw StateError('NativeFrameRenderer has been disposed.');
    }

    if (cefEnabled) {
      final pumpStatus = zikzakCefPump();
      if (pumpStatus != 0) {
        throw StateError('CEF message pump failed with status $pumpStatus.');
      }
      final generation = zikzakCefFrameGeneration();
      if (generation > cefFrameGeneration) {
        final copyStatus = zikzakCefCopyLatestFrame(_destination, byteLength);
        if (copyStatus < 0) {
          throw StateError('CEF frame copy failed with status $copyStatus.');
        }
        if (copyStatus == 1) {
          cefFrameReady = true;
          cefFrameGeneration = generation;
        }
      } else if (cefFrameReady) {
        return Future.value(null);
      }
    }

    if (!cefFrameReady) {
      final result = zikzakRenderTestFrame(
        _destination,
        byteLength,
        frameNumber,
      );
      if (result != 0) {
        throw StateError('Rust frame renderer failed with status $result.');
      }
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

  void navigate(String url) {
    if (!cefEnabled) return;
    final nativeUrl = url.toNativeUtf8();
    try {
      final status = zikzakCefNavigate(nativeUrl.cast());
      if (status != 0) {
        throw StateError('CEF navigation failed with status $status.');
      }
    } finally {
      calloc.free(nativeUrl);
    }
  }

  bool _initializeCef(String runtimeDirectory, String initialUrl) {
    final nativeRuntimeDirectory = runtimeDirectory.toNativeUtf8();
    final nativeInitialUrl = initialUrl.toNativeUtf8();
    try {
      final status = zikzakCefInitialize(
        nativeRuntimeDirectory.cast(),
        nativeInitialUrl.cast(),
      );
      if (status != 0 && status != 1) {
        throw StateError(
          'CEF initialization failed with status $status. '
          'Runtime directory: $runtimeDirectory',
        );
      }
      return status == 1;
    } finally {
      calloc.free(nativeRuntimeDirectory);
      calloc.free(nativeInitialUrl);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_destination);
  }
}
