// SPDX-License-Identifier: UNLICENSED

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import 'native_frame_bindings.dart';

enum BrowserEngine { cef, wpe }

String _displayContextMenuTitle(String title) {
  return title.replaceAllMapped(
    RegExp(r'_(.)'),
    (match) => match.group(1) ?? '',
  );
}

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

  final ui.Offset position;
  final List<BrowserContextMenuItem> items;
}

BrowserEngine _configuredBrowserEngine() {
  return switch (cefTextureBrowserBrowserBackend()) {
    1 => BrowserEngine.cef,
    2 => BrowserEngine.wpe,
    final value => throw StateError('Unknown native browser backend $value.'),
  };
}

final class NativeFrameRenderer {
  NativeFrameRenderer({
    int? engineHandle,
    bool enableBrowser = true,
    String initialUrl = 'https://example.com',
    bool? acceleratedProbe,
    BrowserEngine? browserEngine,
  }) : browserEngine = browserEngine ?? _configuredBrowserEngine(),
       acceleratedProbe =
           enableBrowser &&
           ((browserEngine ?? _configuredBrowserEngine()) ==
                   BrowserEngine.wpe ||
               acceleratedProbe == true ||
               Platform.environment['CEF_TEXTURE_BROWSER_ACCELERATED_PROBE'] ==
                   '1'),
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

      if (enableBrowser) {
        if (this.browserEngine == BrowserEngine.wpe) {
          _initializeWpe(initialUrl);
        } else {
          final executableDirectory = File(Platform.resolvedExecutable).parent;
          final runtimeDirectory = Directory(
            '${executableDirectory.path}${Platform.pathSeparator}lib',
          );
          final reusedRuntime = _initializeCef(
            runtimeDirectory.path,
            initialUrl,
          );
          if (reusedRuntime) {
            navigate(initialUrl);
          }
        }
        browserEnabled = true;
        setVisibility(true);
      }
    } catch (_) {
      if (enableBrowser || this.acceleratedProbe) {
        cefTextureBrowserNativeShutdown();
      }
      calloc.free(_destination);
      _disposed = true;
      rethrow;
    }
  }

  final int apiVersion;
  final BrowserEngine browserEngine;
  final bool acceleratedProbe;
  int _width;
  int _height;
  int _byteLength;

  late Pointer<Uint8> _destination;
  late Uint8List _pixels;
  int? _logicalWidth;
  int? _logicalHeight;
  double? _deviceScaleFactor;
  bool browserEnabled = false;
  bool cefFrameReady = false;
  int cefFrameGeneration = 0;
  bool _proceduralFrameRendered = false;
  int _requestedTextureGeneration = -1;
  int _requestedAcceleratedPaintCount = -1;
  int _lastContextMenuGeneration = 0;
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
  String get browserEngineLabel => switch (browserEngine) {
    BrowserEngine.cef => 'CEF',
    BrowserEngine.wpe => 'WPE WebKit',
  };
  int get acceleratedPaintCount => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpePaintCount()
      : cefTextureBrowserCefAcceleratedPaintCount();
  int get acceleratedValidPaintCount => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeValidPaintCount()
      : cefTextureBrowserCefAcceleratedValidPaintCount();
  int get acceleratedPlaneCount => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpePlaneCount()
      : cefTextureBrowserCefAcceleratedPlaneCount();
  int get acceleratedFormat => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeFormat()
      : cefTextureBrowserCefAcceleratedFormat();
  int get acceleratedModifier => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeModifier()
      : cefTextureBrowserCefAcceleratedModifier();
  int get acceleratedCodedWidth => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeWidth()
      : cefTextureBrowserCefAcceleratedCodedWidth();
  int get acceleratedCodedHeight => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeHeight()
      : cefTextureBrowserCefAcceleratedCodedHeight();
  int get acceleratedVisibleWidth => acceleratedCodedWidth;
  int get acceleratedVisibleHeight => acceleratedCodedHeight;
  int get acceleratedFirstPlaneStride => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeFirstPlaneStride()
      : cefTextureBrowserCefAcceleratedFirstPlaneStride();
  int get dmaBufCallbackGeneration => browserEngine == BrowserEngine.wpe
      ? cefTextureBrowserWpeFrameGeneration()
      : cefTextureBrowserCefDmaBufGeneration();

  Future<ui.Image?> render(int frameNumber) {
    if (_disposed) {
      throw StateError('NativeFrameRenderer has been disposed.');
    }

    if (browserEnabled) {
      final pumpStatus = browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpePump()
          : cefTextureBrowserCefPump();
      if (pumpStatus != 0) {
        throw StateError(
          '$browserEngineLabel message pump failed with status $pumpStatus.',
        );
      }
      if (acceleratedProbe) {
        _requestTextureFrameIfNeeded();
      }
      if (browserEngine == BrowserEngine.wpe) {
        return Future.value(null);
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
    if (!browserEnabled) return;
    final nativeUrl = url.toNativeUtf8();
    try {
      final status = browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeNavigate(nativeUrl.cast())
          : cefTextureBrowserCefNavigate(nativeUrl.cast());
      if (status != 0) {
        throw StateError(
          '$browserEngineLabel navigation failed with status $status.',
        );
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
    if (!browserEnabled || _disposed) return;
    final width = logicalWidth.ceil().clamp(1, 8192);
    final height = logicalHeight.ceil().clamp(1, 8192);
    final scale = deviceScaleFactor.clamp(0.5, 4.0).toDouble();
    if (_logicalWidth == width &&
        _logicalHeight == height &&
        _deviceScaleFactor == scale) {
      return;
    }
    final physicalWidth = (width * scale).ceil().clamp(1, 16384);
    final physicalHeight = (height * scale).ceil().clamp(1, 16384);
    final status = browserEngine == BrowserEngine.wpe
        ? cefTextureBrowserWpeResize(physicalWidth, physicalHeight)
        : cefTextureBrowserCefResize(width, height, scale);
    if (status != 0) {
      throw StateError(
        '$browserEngineLabel surface resize failed with status $status.',
      );
    }
    _logicalWidth = width;
    _logicalHeight = height;
    _deviceScaleFactor = scale;
    if (acceleratedProbe && browserEngine == BrowserEngine.cef) {
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
    _checkInputStatus(
      'focus',
      browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeSetFocus(focused ? 1 : 0)
          : cefTextureBrowserCefSetFocus(focused ? 1 : 0),
    );
  }

  void setVisibility(bool visible) {
    _checkInputStatus(
      'visibility',
      browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeSetVisibility(visible ? 1 : 0)
          : cefTextureBrowserCefSetVisibility(visible ? 1 : 0),
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
      browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeSendMouseMove(
              _physicalInputCoordinate(x),
              _physicalInputCoordinate(y),
              modifiers,
              mouseLeave ? 1 : 0,
            )
          : cefTextureBrowserCefSendMouseMove(
              x,
              y,
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
    _checkInputStatus(
      'mouse button',
      browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeSendMouseButton(
              _physicalInputCoordinate(x),
              _physicalInputCoordinate(y),
              modifiers,
              button,
              mouseUp ? 1 : 0,
              clickCount,
            )
          : cefTextureBrowserCefSendMouseButton(
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
      browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeSendMouseWheel(
              _physicalInputCoordinate(x),
              _physicalInputCoordinate(y),
              modifiers,
              deltaX,
              deltaY,
            )
          : cefTextureBrowserCefSendMouseWheel(x, y, modifiers, deltaX, deltaY),
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
      browserEngine == BrowserEngine.wpe
          ? cefTextureBrowserWpeSendKey(
              eventType,
              modifiers,
              windowsKeyCode,
              nativeKeyCode,
              character,
              unmodifiedCharacter,
            )
          : cefTextureBrowserCefSendKey(
              eventType,
              modifiers,
              windowsKeyCode,
              nativeKeyCode,
              character,
              unmodifiedCharacter,
            ),
    );
  }

  NativeBrowserContextMenu? takeContextMenu() {
    if (browserEngine != BrowserEngine.wpe || !browserEnabled || _disposed) {
      return null;
    }
    final generation = cefTextureBrowserWpeContextMenuGeneration();
    if (generation == 0 || generation == _lastContextMenuGeneration) {
      return null;
    }
    _lastContextMenuGeneration = generation;
    final itemCount = cefTextureBrowserWpeContextMenuItemCount();
    final items = <BrowserContextMenuItem>[];
    for (var index = 0; index < itemCount; index += 1) {
      final length = cefTextureBrowserWpeContextMenuItemTitleLength(index);
      var title = '';
      if (length > 0) {
        final destination = calloc<Uint8>(length);
        try {
          final copied = cefTextureBrowserWpeContextMenuItemCopyTitle(
            index,
            destination,
            length,
          );
          if (copied > 0) {
            title = _displayContextMenuTitle(
              utf8.decode(
                destination.asTypedList(copied),
                allowMalformed: true,
              ),
            );
          }
        } finally {
          calloc.free(destination);
        }
      }
      items.add(
        BrowserContextMenuItem(
          index: index,
          title: title,
          isSeparator:
              cefTextureBrowserWpeContextMenuItemIsSeparator(index) != 0,
          isEnabled: cefTextureBrowserWpeContextMenuItemIsEnabled(index) != 0,
        ),
      );
    }
    final scale = _deviceScaleFactor ?? 1.0;
    return NativeBrowserContextMenu(
      position: ui.Offset(
        cefTextureBrowserWpeContextMenuX() / scale,
        cefTextureBrowserWpeContextMenuY() / scale,
      ),
      items: items,
    );
  }

  void activateContextMenuItem(int index) {
    final status = cefTextureBrowserWpeContextMenuActivate(index);
    if (status != 0) {
      throw StateError(
        '$browserEngineLabel context-menu action failed with status $status.',
      );
    }
  }

  void dismissContextMenu() {
    if (browserEngine == BrowserEngine.wpe && !_disposed) {
      cefTextureBrowserWpeContextMenuDismiss();
    }
  }

  void _checkInputStatus(String operation, int status) {
    if (!browserEnabled || _disposed) return;
    if (status != 0) {
      throw StateError(
        '$browserEngineLabel $operation failed with status $status.',
      );
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

  void _initializeWpe(String initialUrl) {
    final nativeInitialUrl = initialUrl.toNativeUtf8();
    try {
      final status = cefTextureBrowserWpeInitialize(nativeInitialUrl.cast());
      if (status != 0 && status != 1) {
        throw StateError('WPE initialization failed with status $status.');
      }
      if (status == 1) {
        final navigationStatus = cefTextureBrowserWpeNavigate(
          nativeInitialUrl.cast(),
        );
        if (navigationStatus != 0) {
          throw StateError(
            'WPE navigation failed with status $navigationStatus.',
          );
        }
      }
    } finally {
      calloc.free(nativeInitialUrl);
    }
  }

  int _physicalInputCoordinate(int logicalCoordinate) {
    final scale = _deviceScaleFactor ?? 1.0;
    return (logicalCoordinate * scale).round();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (browserEnabled || acceleratedProbe) {
      final shutdownStatus = cefTextureBrowserNativeShutdown();
      if (shutdownStatus < 0) {
        stderr.writeln(
          'Native browser shutdown failed with status $shutdownStatus.',
        );
      }
      browserEnabled = false;
    }
    calloc.free(_destination);
  }
}
