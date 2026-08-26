// SPDX-License-Identifier: UNLICENSED

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'src/cef_keyboard.dart';
import 'src/native_frame_renderer.dart';

Future<void> main() async {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (kDebugMode && !isFlutterTest) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  final engineHandle = await EngineContext.instance.getEngineHandle();
  final renderer = NativeFrameRenderer(engineHandle: engineHandle);
  runApp(ProbeApp(renderer: renderer));
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({
    super.key,
    this.animate = true,
    this.enableCef = true,
    this.renderer,
  });

  final bool animate;
  final bool enableCef;
  final NativeFrameRenderer? renderer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CEF Texture Browser',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff695de9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ProbePage(
        animate: animate,
        enableCef: enableCef,
        renderer: renderer,
      ),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({
    super.key,
    required this.animate,
    required this.enableCef,
    this.renderer,
  });

  final bool animate;
  final bool enableCef;
  final NativeFrameRenderer? renderer;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> with WidgetsBindingObserver {
  final _addressController = TextEditingController(text: 'https://example.com');
  final _surfaceFocusNode = FocusNode(debugLabel: 'CEF browser surface');
  NativeFrameRenderer? _renderer;
  Timer? _frameTimer;
  ui.Image? _image;
  Object? _error;
  int _frameNumber = 0;
  int _framesRendered = 0;
  int _lastAcceleratedPaintCount = 0;
  bool _frameInFlight = false;
  int _pressedButtons = 0;
  Offset _lastPointerPosition = Offset.zero;
  Size? _requestedSurfaceSize;
  double? _requestedDeviceScaleFactor;
  bool _resizeScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _renderer =
          widget.renderer ?? NativeFrameRenderer(enableCef: widget.enableCef);
      Timer.run(() {
        if (!mounted) return;
        _renderNextFrame();
        _startFrameTimer();
      });
    } catch (error) {
      _error = error;
    }
  }

  Future<void> _renderNextFrame() async {
    final renderer = _renderer;
    if (!mounted || renderer == null || _frameInFlight) return;

    _frameInFlight = true;
    try {
      final nextImage = await renderer.render(_frameNumber++);
      final acceleratedPaintCount = renderer.acceleratedPaintCount;
      if (nextImage == null) {
        if (mounted && acceleratedPaintCount != _lastAcceleratedPaintCount) {
          setState(() => _lastAcceleratedPaintCount = acceleratedPaintCount);
        }
        return;
      }
      if (!mounted) {
        nextImage.dispose();
        return;
      }
      final previousImage = _image;
      setState(() {
        _image = nextImage;
        _framesRendered += 1;
        _lastAcceleratedPaintCount = acceleratedPaintCount;
      });
      if (previousImage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previousImage.dispose();
        });
      }
    } catch (error) {
      _stopFrameTimer();
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      _frameInFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFrameTimer();
    _addressController.dispose();
    _surfaceFocusNode.dispose();
    _image?.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _renderer?.dispose();
      _renderer = null;
      _stopFrameTimer();
      return;
    }
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _runCefAction(() => _renderer?.setVisibility(visible));
    if (!widget.animate) return;
    if (visible) {
      _startFrameTimer();
    } else {
      _stopFrameTimer();
    }
  }

  void _startFrameTimer() {
    if (!widget.animate || _frameTimer != null) return;
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _renderNextFrame(),
    );
  }

  void _stopFrameTimer() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    return Scaffold(
      appBar: AppBar(title: const Text('CEF Texture Browser')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusChip(
                  icon: _error == null ? Icons.memory : Icons.error_outline,
                  label: _error == null
                      ? 'Rust native asset online'
                      : 'Rust native asset failed',
                ),
                if (renderer != null)
                  _StatusChip(
                    icon: Icons.integration_instructions_outlined,
                    label: 'ABI v${renderer.apiVersion}',
                  ),
                if (renderer != null)
                  _StatusChip(
                    icon: Icons.aspect_ratio,
                    label: renderer.acceleratedProbe
                        ? '${renderer.textureWidth}×${renderer.textureHeight} '
                              'GL · ${_pixelScaleLabel(renderer)}'
                        : '${renderer.width}×${renderer.height} RGBA',
                  ),
                if (renderer?.cefEnabled ?? false)
                  _StatusChip(
                    icon: Icons.language,
                    label: renderer!.acceleratedProbe
                        ? _acceleratedProbeLabel(renderer)
                        : renderer.cefFrameReady
                        ? 'CEF CPU OSR · frame ${renderer.cefFrameGeneration}'
                        : 'CEF CPU OSR · waiting for first paint',
                  ),
                if ((renderer?.acceleratedProbe ?? false) &&
                    renderer!.acceleratedPaintCount > 0)
                  _StatusChip(
                    icon: Icons.data_object,
                    label: _acceleratedMetadataLabel(renderer),
                  ),
                if ((renderer?.acceleratedProbe ?? false) &&
                    renderer!.textureId > 0)
                  _StatusChip(
                    icon: Icons.texture,
                    label:
                        'Irondash FlTextureGL · id ${renderer.textureId} · '
                        'name ${renderer.textureGlName} · '
                        '${_textureTransportLabel(renderer)}',
                  ),
                _StatusChip(
                  icon: Icons.movie_filter_outlined,
                  label: renderer?.acceleratedProbe ?? false
                      ? 'Copies: ${renderer!.textureDmaBufCopyCount}'
                      : 'Frames: $_framesRendered',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('address-field'),
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _navigate(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('navigate-button'),
                  onPressed: renderer?.cefEnabled ?? false ? _navigate : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Go'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff090c16),
                  border: Border.all(color: const Color(0xff343a55)),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: _buildSurface(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              renderer?.acceleratedProbe ?? false
                  ? 'Accelerated probe mode displays an Irondash-managed '
                        'FlTextureGL surface. Valid CEF DMA-BUF frames are '
                        'imported through EGL and copied into the Flutter-owned '
                        'texture without a CPU pixel readback.'
                  : 'This frame is generated in Rust, written directly into '
                        'FFI memory owned by Dart, and uploaded as a Flutter '
                        'image. The procedural frame remains visible only '
                        'until CEF delivers its first off-screen paint callback.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _acceleratedProbeLabel(NativeFrameRenderer renderer) {
    final paints = renderer.acceleratedPaintCount;
    if (paints == 0) return 'CEF DMA-BUF probe · waiting';
    final valid = renderer.acceleratedValidPaintCount;
    return 'CEF DMA-BUF · $valid/$paints valid · '
        '${renderer.acceleratedCodedWidth}×${renderer.acceleratedCodedHeight} · '
        '${renderer.acceleratedPlaneCount} plane(s)';
  }

  String _acceleratedMetadataLabel(NativeFrameRenderer renderer) {
    final format = switch (renderer.acceleratedFormat) {
      0 => 'RGBA8888',
      1 => 'BGRA8888',
      final value => 'format $value',
    };
    return '$format · mod '
        '0x${renderer.acceleratedModifier.toRadixString(16)} · '
        '${renderer.acceleratedFirstPlaneStride} B/row';
  }

  String _textureTransportLabel(NativeFrameRenderer renderer) {
    final generation = renderer.textureDmaBufGeneration;
    final status = renderer.textureDmaBufStatus;
    if (generation == 0) {
      return 'test frame · callback ${renderer.dmaBufCallbackGeneration}';
    }
    if (status == 0) {
      return 'DMA-BUF frame $generation · '
          '${renderer.textureDmaBufLastCopyMicros}µs last · '
          '${renderer.textureDmaBufMaxCopyMicros}µs max · '
          '${renderer.textureDmaBufFenceFallbackCount} fallback';
    }
    return 'DMA-BUF error $status';
  }

  String _pixelScaleLabel(NativeFrameRenderer renderer) {
    final exact =
        renderer.textureWidth == renderer.acceleratedVisibleWidth &&
        renderer.textureHeight == renderer.acceleratedVisibleHeight;
    return exact ? '1:1' : 'waiting for 1:1';
  }

  void _navigate() {
    final renderer = _renderer;
    if (renderer == null) return;
    var url = _addressController.text.trim();
    if (url.isEmpty) return;
    if (!url.contains('://')) url = 'https://$url';
    _addressController.value = TextEditingValue(
      text: url,
      selection: TextSelection.collapsed(offset: url.length),
    );
    renderer.navigate(url);
  }

  Widget _buildSurface() {
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            error.toString(),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleSurfaceResize(size, MediaQuery.devicePixelRatioOf(context));
        return Focus(
          focusNode: _surfaceFocusNode,
          onFocusChange: (focused) {
            _runCefAction(() => _renderer?.setFocus(focused));
          },
          onKeyEvent: _handleKeyEvent,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onExit: _handlePointerExit,
            child: Listener(
              key: const ValueKey('browser-surface'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              onPointerMove: _handlePointerMove,
              onPointerHover: _handlePointerMove,
              onPointerSignal: _handlePointerSignal,
              child:
                  (_renderer?.acceleratedProbe ?? false) &&
                      (_renderer?.textureId ?? 0) > 0
                  ? Texture(
                      textureId: _renderer!.textureId,
                      filterQuality: FilterQuality.none,
                    )
                  : _image != null
                  ? RawImage(
                      image: _image,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      },
    );
  }

  void _scheduleSurfaceResize(Size size, double deviceScaleFactor) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    if (_requestedSurfaceSize == size &&
        _requestedDeviceScaleFactor == deviceScaleFactor) {
      return;
    }
    _requestedSurfaceSize = size;
    _requestedDeviceScaleFactor = deviceScaleFactor;
    if (_resizeScheduled) return;
    _resizeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resizeScheduled = false;
      if (!mounted) return;
      final requestedSize = _requestedSurfaceSize;
      final requestedScale = _requestedDeviceScaleFactor;
      if (requestedSize == null || requestedScale == null) return;
      _runCefAction(
        () => _renderer?.resizeSurface(
          logicalWidth: requestedSize.width,
          logicalHeight: requestedSize.height,
          deviceScaleFactor: requestedScale,
        ),
      );
    });
  }

  void _handlePointerMove(PointerEvent event) {
    _lastPointerPosition = event.localPosition;
    final point = _cefPoint(event.localPosition);
    _runCefAction(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _cefModifiers(buttons: event.buttons),
      ),
    );
  }

  void _handlePointerExit(PointerExitEvent event) {
    _lastPointerPosition = event.localPosition;
    final point = _cefPoint(event.localPosition);
    _runCefAction(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _cefModifiers(buttons: event.buttons),
        mouseLeave: true,
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _surfaceFocusNode.requestFocus();
    _lastPointerPosition = event.localPosition;
    final addedButtons = event.buttons & ~_pressedButtons;
    _pressedButtons = event.buttons;
    _sendChangedButtons(event.localPosition, addedButtons, mouseUp: false);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _lastPointerPosition = event.localPosition;
    final releasedButtons = _pressedButtons & ~event.buttons;
    _sendChangedButtons(event.localPosition, releasedButtons, mouseUp: true);
    _pressedButtons = event.buttons;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _sendChangedButtons(_lastPointerPosition, _pressedButtons, mouseUp: true);
    _pressedButtons = 0;
  }

  void _sendChangedButtons(
    Offset position,
    int buttons, {
    required bool mouseUp,
  }) {
    final point = _cefPoint(position);
    for (final entry in const <(int, int)>[
      (kPrimaryMouseButton, 0),
      (kMiddleMouseButton, 1),
      (kSecondaryMouseButton, 2),
    ]) {
      if (buttons & entry.$1 == 0) continue;
      _runCefAction(
        () => _renderer?.sendMouseButton(
          x: point.$1,
          y: point.$2,
          modifiers: _cefModifiers(buttons: _pressedButtons),
          button: entry.$2,
          mouseUp: mouseUp,
        ),
      );
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _lastPointerPosition = event.localPosition;
    final point = _cefPoint(event.localPosition);
    _runCefAction(
      () => _renderer?.sendMouseWheel(
        x: point.$1,
        y: point.$2,
        modifiers: _cefModifiers(buttons: event.buttons),
        deltaX: -event.scrollDelta.dx.round(),
        deltaY: -event.scrollDelta.dy.round(),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final windowsKeyCode = cefWindowsKeyCode(event.logicalKey);
    if (windowsKeyCode == null) return KeyEventResult.ignored;
    final modifiers = _cefModifiers(buttons: _pressedButtons);
    final eventType = event is KeyUpEvent
        ? cefKeyEventKeyUp
        : cefKeyEventRawKeyDown;
    _runCefAction(
      () => _renderer?.sendKey(
        eventType: eventType,
        modifiers: modifiers,
        windowsKeyCode: windowsKeyCode,
        nativeKeyCode: event.physicalKey.usbHidUsage,
      ),
    );

    final character = event.character;
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyUpEvent &&
        character != null &&
        character.isNotEmpty &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed) {
      for (final codeUnit in character.codeUnits) {
        _runCefAction(
          () => _renderer?.sendKey(
            eventType: cefKeyEventCharacter,
            modifiers: modifiers,
            windowsKeyCode: windowsKeyCode,
            nativeKeyCode: event.physicalKey.usbHidUsage,
            character: codeUnit,
            unmodifiedCharacter: codeUnit,
          ),
        );
      }
    }
    return KeyEventResult.handled;
  }

  (int, int) _cefPoint(Offset position) {
    final size = _requestedSurfaceSize;
    final maxX = size == null ? 16383 : (size.width.ceil() - 1).clamp(0, 16383);
    final maxY = size == null
        ? 16383
        : (size.height.ceil() - 1).clamp(0, 16383);
    return (
      position.dx.floor().clamp(0, maxX),
      position.dy.floor().clamp(0, maxY),
    );
  }

  int _cefModifiers({required int buttons}) {
    final keyboard = HardwareKeyboard.instance;
    var modifiers = cefKeyboardModifiers(
      shift: keyboard.isShiftPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
      capsLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock),
      numLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock),
    );
    if (buttons & kPrimaryMouseButton != 0) {
      modifiers |= cefEventFlagLeftMouseButton;
    }
    if (buttons & kMiddleMouseButton != 0) {
      modifiers |= cefEventFlagMiddleMouseButton;
    }
    if (buttons & kSecondaryMouseButton != 0) {
      modifiers |= cefEventFlagRightMouseButton;
    }
    return modifiers;
  }

  void _runCefAction(void Function() action) {
    try {
      action();
    } catch (error) {
      _stopFrameTimer();
      if (mounted) setState(() => _error = error);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 7),
            Text(label),
          ],
        ),
      ),
    );
  }
}
