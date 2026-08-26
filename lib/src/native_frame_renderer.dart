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
    int? engineHandle,
    bool enableCef = true,
    String initialUrl = 'https://example.com',
    bool? acceleratedProbe,
  }) : acceleratedProbe =
           acceleratedProbe ??
           Platform.environment['CEF_TEXTURE_BROWSER_ACCELERATED_PROBE'] == '1',
       apiVersion = cefTextureBrowserApiVersion(),
       _width = cefTextureBrowserFrameWidth(),
       _height = cefTextureBrowserFrameHeight(),
       _byteLength = cefTextureBrowserFrameByteLength() {
    final expectedLength = _width * _height * 4;
    if (_byteLength != expectedLength) {
      throw StateError(
        'Rust ABI returned $_byteLength bytes for a '
        '${_width}x$_height RGBA frame; expected $expectedLength.',
      );
    }
    _allocateBuffer(_byteLength);

    try {
      if (this.acceleratedProbe) {
        if (engineHandle == null) {
          throw ArgumentError.notNull('engineHandle');
        }
        final textureStatus = cefTextureBrowserFlutterTextureInitialize(
          engineHandle,
        );
        if (textureStatus != 0 && textureStatus != 1) {
          throw StateError(
            'Irondash Flutter texture initialization failed with status '
            '$textureStatus.',
          );
        }
      }

      if (enableCef) {
        final executableDirectory = File(Platform.resolvedExecutable).parent;
        final runtimeDirectory = Directory(
          '${executableDirectory.path}${Platform.pathSeparator}lib',
        );
        final reusedRuntime = _initializeCef(runtimeDirectory.path, initialUrl);
        cefEnabled = true;
        setVisibility(true);
        if (reusedRuntime) {
          navigate(initialUrl);
        }
      }
    } catch (_) {
      if (enableCef || this.acceleratedProbe) {
        cefTextureBrowserNativeShutdown();
      }
      calloc.free(_destination);
      _disposed = true;
      rethrow;
    }
  }

  final int apiVersion;
  final bool acceleratedProbe;
  int _width;
  int _height;
  int _byteLength;

  late Pointer<Uint8> _destination;
  late Uint8List _pixels;
  int? _logicalWidth;
  int? _logicalHeight;
  double? _deviceScaleFactor;
  bool cefEnabled = false;
  bool cefFrameReady = false;
  int cefFrameGeneration = 0;
  bool _proceduralFrameRendered = false;
  int _requestedTextureGeneration = -1;
  int _requestedAcceleratedPaintCount = -1;
  bool _disposed = false;

  int get width => _width;
  int get height => _height;
  int get byteLength => _byteLength;
  int get textureId => cefTextureBrowserFlutterTextureId();
  int get textureWidth => cefTextureBrowserFlutterTextureWidth();
  int get textureHeight => cefTextureBrowserFlutterTextureHeight();
  int get textureGeneration => cefTextureBrowserFlutterTextureGeneration();
  int get textureGlName => cefTextureBrowserFlutterTextureGlName();
  bool get textureGlContextReady =>
      cefTextureBrowserFlutterTextureEglDisplay() != 0 &&
      cefTextureBrowserFlutterTextureEglContext() != 0;
  int get textureDmaBufGeneration =>
      cefTextureBrowserFlutterTextureDmaBufGeneration();
  int get textureDmaBufStatus => cefTextureBrowserFlutterTextureDmaBufStatus();
  int get textureDmaBufCopyCount =>
      cefTextureBrowserFlutterTextureDmaBufCopyCount();
  int get textureDmaBufLastCopyMicros =>
      cefTextureBrowserFlutterTextureDmaBufLastCopyMicros();
  int get textureDmaBufMaxCopyMicros =>
      cefTextureBrowserFlutterTextureDmaBufMaxCopyMicros();
  int get textureDmaBufFenceFallbackCount =>
      cefTextureBrowserFlutterTextureDmaBufFenceFallbackCount();
  int get acceleratedPaintCount => cefTextureBrowserCefAcceleratedPaintCount();
  int get acceleratedValidPaintCount =>
      cefTextureBrowserCefAcceleratedValidPaintCount();
  int get acceleratedPlaneCount => cefTextureBrowserCefAcceleratedPlaneCount();
  int get acceleratedFormat => cefTextureBrowserCefAcceleratedFormat();
  int get acceleratedModifier => cefTextureBrowserCefAcceleratedModifier();
  int get acceleratedCodedWidth => cefTextureBrowserCefAcceleratedCodedWidth();
  int get acceleratedCodedHeight =>
      cefTextureBrowserCefAcceleratedCodedHeight();
  int get acceleratedVisibleWidth =>
      cefTextureBrowserCefAcceleratedVisibleWidth();
  int get acceleratedVisibleHeight =>
      cefTextureBrowserCefAcceleratedVisibleHeight();
  int get acceleratedFirstPlaneStride =>
      cefTextureBrowserCefAcceleratedFirstPlaneStride();
  int get dmaBufCallbackGeneration => cefTextureBrowserCefDmaBufGeneration();

  Future<ui.Image?> render(int frameNumber) {
    if (_disposed) {
      throw StateError('NativeFrameRenderer has been disposed.');
    }

    if (cefEnabled) {
      final pumpStatus = cefTextureBrowserCefPump();
      if (pumpStatus != 0) {
        throw StateError('CEF message pump failed with status $pumpStatus.');
      }
      if (acceleratedProbe) {
        _requestTextureFrameIfNeeded();
      }
      final generation = cefTextureBrowserCefFrameGeneration();
      if (generation > cefFrameGeneration) {
        final frameWidth = cefTextureBrowserCefFrameWidth();
        final frameHeight = cefTextureBrowserCefFrameHeight();
        final frameByteLength = cefTextureBrowserCefFrameByteLength();
        final expectedLength = frameWidth * frameHeight * 4;
        if (frameWidth <= 0 ||
            frameHeight <= 0 ||
            frameByteLength != expectedLength) {
          throw StateError(
            'CEF reported an invalid frame: '
            '${frameWidth}x$frameHeight, $frameByteLength bytes.',
          );
        }
        _resizeBuffer(frameWidth, frameHeight, frameByteLength);
        final copyStatus = cefTextureBrowserCefCopyLatestFrame(
          _destination,
          _byteLength,
        );
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
      if (acceleratedProbe && _proceduralFrameRendered) {
        return Future.value(null);
      }
      final result = cefTextureBrowserRenderTestFrame(
        _destination,
        _byteLength,
        frameNumber,
      );
      if (result != 0) {
        throw StateError('Rust frame renderer failed with status $result.');
      }
      _proceduralFrameRendered = true;
    }

    final image = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixels,
      _width,
      _height,
      ui.PixelFormat.rgba8888,
      image.complete,
    );
    return image.future;
  }

  void navigate(String url) {
    if (!cefEnabled) return;
    final nativeUrl = url.toNativeUtf8();
    try {
      final status = cefTextureBrowserCefNavigate(nativeUrl.cast());
      if (status != 0) {
        throw StateError('CEF navigation failed with status $status.');
      }
    } finally {
      calloc.free(nativeUrl);
    }
  }

  void resizeSurface({
    required double logicalWidth,
    required double logicalHeight,
    required double deviceScaleFactor,
  }) {
    if (!cefEnabled || _disposed) return;
    final width = logicalWidth.ceil().clamp(1, 8192);
    final height = logicalHeight.ceil().clamp(1, 8192);
    final scale = deviceScaleFactor.clamp(0.5, 4.0).toDouble();
    if (_logicalWidth == width &&
        _logicalHeight == height &&
        _deviceScaleFactor == scale) {
      return;
    }
    final status = cefTextureBrowserCefResize(width, height, scale);
    if (status != 0) {
      throw StateError('CEF surface resize failed with status $status.');
    }
    _logicalWidth = width;
    _logicalHeight = height;
    _deviceScaleFactor = scale;
    if (acceleratedProbe) {
      final physicalWidth = (width * scale).ceil().clamp(1, 16384);
      final physicalHeight = (height * scale).ceil().clamp(1, 16384);
      final textureStatus = cefTextureBrowserFlutterTextureResize(
        physicalWidth,
        physicalHeight,
      );
      if (textureStatus != 0) {
        throw StateError(
          'Flutter GL texture resize failed with status $textureStatus.',
        );
      }
    }
  }

  void _requestTextureFrameIfNeeded() {
    if (textureId <= 0) return;
    final generation = textureGeneration;
    final paintCount = acceleratedPaintCount;
    if (generation == _requestedTextureGeneration &&
        paintCount == _requestedAcceleratedPaintCount) {
      return;
    }
    final status = cefTextureBrowserFlutterTextureRequestFrame();
    if (status != 0) {
      throw StateError(
        'Flutter GL texture frame request failed with status $status.',
      );
    }
    _requestedTextureGeneration = generation;
    _requestedAcceleratedPaintCount = paintCount;
  }

  void setFocus(bool focused) {
    _checkInputStatus('focus', cefTextureBrowserCefSetFocus(focused ? 1 : 0));
  }

  void setVisibility(bool visible) {
    _checkInputStatus(
      'visibility',
      cefTextureBrowserCefSetVisibility(visible ? 1 : 0),
    );
  }

  void sendMouseMove({
    required int x,
    required int y,
    required int modifiers,
    bool mouseLeave = false,
  }) {
    _checkInputStatus(
      'mouse move',
      cefTextureBrowserCefSendMouseMove(x, y, modifiers, mouseLeave ? 1 : 0),
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
    _checkInputStatus(
      'mouse button',
      cefTextureBrowserCefSendMouseButton(
        x,
        y,
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
    _checkInputStatus(
      'mouse wheel',
      cefTextureBrowserCefSendMouseWheel(x, y, modifiers, deltaX, deltaY),
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
    _checkInputStatus(
      'key',
      cefTextureBrowserCefSendKey(
        eventType,
        modifiers,
        windowsKeyCode,
        nativeKeyCode,
        character,
        unmodifiedCharacter,
      ),
    );
  }

  void _checkInputStatus(String operation, int status) {
    if (!cefEnabled || _disposed) return;
    if (status != 0) {
      throw StateError('CEF $operation failed with status $status.');
    }
  }

  void _allocateBuffer(int length) {
    _destination = calloc<Uint8>(length);
    _pixels = _destination.asTypedList(length);
  }

  void _resizeBuffer(int width, int height, int length) {
    if (_byteLength != length) {
      calloc.free(_destination);
      _byteLength = length;
      _allocateBuffer(length);
    }
    _width = width;
    _height = height;
  }

  bool _initializeCef(String runtimeDirectory, String initialUrl) {
    final nativeRuntimeDirectory = runtimeDirectory.toNativeUtf8();
    final nativeInitialUrl = initialUrl.toNativeUtf8();
    try {
      final status = cefTextureBrowserCefInitializeWithOptions(
        nativeRuntimeDirectory.cast(),
        nativeInitialUrl.cast(),
        acceleratedProbe ? 1 : 0,
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
    if (cefEnabled || acceleratedProbe) {
      final shutdownStatus = cefTextureBrowserNativeShutdown();
      if (shutdownStatus < 0) {
        stderr.writeln(
          'Native browser shutdown failed with status $shutdownStatus.',
        );
      }
      cefEnabled = false;
    }
    calloc.free(_destination);
  }
}
