// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_webview_controller.dart';
import 'native_frame_renderer.dart';
import 'wpe_keyboard.dart';

/// Linux implementation of [PlatformWebViewWidget].
class LinuxWebViewWidget extends PlatformWebViewWidget {
  /// Creates a Linux WebView widget delegate.
  LinuxWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(params) {
    if (params.controller is! LinuxWebViewController) {
      throw ArgumentError.value(
        params.controller,
        'params.controller',
        'Expected a LinuxWebViewController.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => _LinuxWebViewSurface(
    key: params.key,
    controller: params.controller as LinuxWebViewController,
  );
}

class _LinuxWebViewSurface extends StatefulWidget {
  const _LinuxWebViewSurface({super.key, required this.controller});

  final LinuxWebViewController controller;

  @override
  State<_LinuxWebViewSurface> createState() => _LinuxWebViewSurfaceState();
}

class _LinuxWebViewSurfaceState extends State<_LinuxWebViewSurface>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Linux WebView');
  final GlobalKey _surfaceKey = GlobalKey();
  NativeFrameRenderer? _renderer;
  Timer? _frameTimer;
  Object? _error;
  int _pressedButtons = 0;
  Offset _lastPointerPosition = Offset.zero;
  Size? _requestedSize;
  double? _requestedScale;
  bool _resizeScheduled = false;
  bool _contextMenuOpen = false;
  Future<void> _inputQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_attach());
  }

  Future<void> _attach() async {
    try {
      final renderer = await widget.controller.attachRenderer();
      if (!mounted) {
        widget.controller.detachRenderer(renderer);
        return;
      }
      setState(() => _renderer = renderer);
      _frameTimer = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _pump(),
      );
      _pump();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _pump() {
    final renderer = _renderer;
    if (!mounted || renderer == null) return;
    try {
      final frameChanged = renderer.pump();
      if (frameChanged && renderer.paintCount > 0) {
        widget.controller.didPaintFrame();
      }
      final clipboardText = renderer.takeClipboardText();
      if (clipboardText != null) {
        unawaited(Clipboard.setData(ClipboardData(text: clipboardText)));
      }
      final menu = renderer.takeContextMenu();
      if (menu != null) unawaited(_showContextMenu(menu));
    } catch (error) {
      _frameTimer?.cancel();
      _frameTimer = null;
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final renderer = _renderer;
    if (renderer == null) return;
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    try {
      renderer.setVisibility(visible);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _focusNode.dispose();
    final renderer = _renderer;
    if (renderer != null) widget.controller.detachRenderer(renderer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Linux WebView failed: $error'),
          ),
        ),
      );
    }
    final renderer = _renderer;
    if (renderer == null || renderer.textureId <= 0) {
      return const ColoredBox(
        color: Color(0xff10131d),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 1,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 1,
        );
        _scheduleResize(size, MediaQuery.devicePixelRatioOf(context));
        return Focus(
          focusNode: _focusNode,
          onFocusChange: (focused) {
            _safeInput(() => renderer.setFocus(focused));
            if (focused) unawaited(_syncSystemClipboardToBrowser());
          },
          onKeyEvent: _handleKeyEvent,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onHover: _handlePointerHover,
            onExit: _handlePointerExit,
            child: Listener(
              key: _surfaceKey,
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              onPointerSignal: _handlePointerSignal,
              child: Texture(
                textureId: renderer.textureId,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        );
      },
    );
  }

  void _scheduleResize(Size size, double scale) {
    if (_requestedSize == size && _requestedScale == scale) return;
    _requestedSize = size;
    _requestedScale = scale;
    if (_resizeScheduled) return;
    _resizeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resizeScheduled = false;
      final renderer = _renderer;
      final requested = _requestedSize;
      if (!mounted || renderer == null || requested == null) return;
      _safeInput(
        () => renderer.resizeSurface(
          logicalWidth: requested.width,
          logicalHeight: requested.height,
          deviceScaleFactor: _requestedScale ?? 1,
        ),
      );
    });
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _lastPointerPosition = event.localPosition;
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
      ),
    );
  }

  void _handlePointerExit(PointerExitEvent event) {
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
        mouseLeave: true,
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    _lastPointerPosition = event.localPosition;
    final changed = event.buttons & ~_pressedButtons;
    _pressedButtons = event.buttons;
    _sendChangedButtons(changed, event.localPosition, mouseUp: false);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _lastPointerPosition = event.localPosition;
    final released = _pressedButtons & ~event.buttons;
    final pressed = event.buttons & ~_pressedButtons;
    if (released != 0) {
      _sendChangedButtons(released, event.localPosition, mouseUp: true);
    }
    if (pressed != 0) {
      _sendChangedButtons(pressed, event.localPosition, mouseUp: false);
    }
    _pressedButtons = event.buttons;
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    _lastPointerPosition = event.localPosition;
    final released = _pressedButtons & ~event.buttons;
    _sendChangedButtons(released, event.localPosition, mouseUp: true);
    _pressedButtons = event.buttons;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _sendChangedButtons(_pressedButtons, _lastPointerPosition, mouseUp: true);
    _pressedButtons = 0;
  }

  void _sendChangedButtons(
    int buttons,
    Offset position, {
    required bool mouseUp,
  }) {
    final point = _surfacePoint(position);
    for (final entry in const <(int, int)>[
      (kPrimaryMouseButton, 0),
      (kMiddleMouseButton, 1),
      (kSecondaryMouseButton, 2),
    ]) {
      if (buttons & entry.$1 == 0) continue;
      final modifiers = _modifiers(buttons: _pressedButtons);
      void send() => _safeInput(
        () => _renderer?.sendMouseButton(
          x: point.$1,
          y: point.$2,
          modifiers: modifiers,
          button: entry.$2,
          mouseUp: mouseUp,
        ),
      );

      _enqueueInput(() async {
        if (entry.$1 == kSecondaryMouseButton && !mouseUp) {
          await _syncSystemClipboardToBrowser();
        }
        send();
      });
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseWheel(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: _pressedButtons),
        deltaX: event.scrollDelta.dx.round(),
        deltaY: event.scrollDelta.dy.round(),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final windowsKeyCode = webViewWindowsKeyCode(event.logicalKey);
    if (windowsKeyCode == null) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final modifiers = webViewKeyboardModifiers(
      shift: keyboard.isShiftPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
      capsLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock),
      numLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock),
    );
    final character = event.character;
    final characterCode = character == null || character.isEmpty
        ? 0
        : character.runes.first;
    final isPaste =
        event is! KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);

    _enqueueInput(() async {
      if (isPaste) await _syncSystemClipboardToBrowser();
      _renderer?.sendKey(
        eventType: event is KeyUpEvent
            ? webViewKeyEventKeyUp
            : webViewKeyEventRawKeyDown,
        modifiers: modifiers,
        windowsKeyCode: windowsKeyCode,
        nativeKeyCode: event.physicalKey.usbHidUsage,
        character: characterCode,
        unmodifiedCharacter: characterCode,
      );
    });
    return KeyEventResult.handled;
  }

  Future<void> _syncSystemClipboardToBrowser() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    _renderer?.setClipboardText(data?.text ?? '');
  }

  void _enqueueInput(Future<void> Function() action) {
    _inputQueue = _inputQueue.then((_) => action()).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  void _safeInput(void Function() action) {
    try {
      action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  (int, int) _surfacePoint(Offset position) {
    final size = _requestedSize;
    final maxX = size == null ? 16383 : (size.width.ceil() - 1).clamp(0, 16383);
    final maxY = size == null
        ? 16383
        : (size.height.ceil() - 1).clamp(0, 16383);
    return (
      position.dx.round().clamp(0, maxX),
      position.dy.round().clamp(0, maxY),
    );
  }

  int _modifiers({required int buttons}) {
    final keyboard = HardwareKeyboard.instance;
    return webViewKeyboardModifiers(
          shift: keyboard.isShiftPressed,
          control: keyboard.isControlPressed,
          alt: keyboard.isAltPressed,
          meta: keyboard.isMetaPressed,
          capsLock: keyboard.lockModesEnabled.contains(
            KeyboardLockMode.capsLock,
          ),
          numLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock),
        ) |
        (buttons & kPrimaryMouseButton != 0
            ? webViewEventFlagLeftMouseButton
            : 0) |
        (buttons & kMiddleMouseButton != 0
            ? webViewEventFlagMiddleMouseButton
            : 0) |
        (buttons & kSecondaryMouseButton != 0
            ? webViewEventFlagRightMouseButton
            : 0);
  }

  Future<void> _showContextMenu(NativeBrowserContextMenu menu) async {
    if (_contextMenuOpen || !mounted || menu.items.isEmpty) return;
    final surfaceBox =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (surfaceBox == null || overlayBox == null) return;
    final global = surfaceBox.localToGlobal(
      menu.position,
      ancestor: overlayBox,
    );
    _contextMenuOpen = true;
    final entries = <PopupMenuEntry<int>>[];
    for (final item in menu.items) {
      if (item.isSeparator) {
        entries.add(const PopupMenuDivider());
      } else {
        entries.add(
          PopupMenuItem<int>(
            value: item.index,
            enabled: item.isEnabled,
            child: Text(item.title),
          ),
        );
      }
    }
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        overlayBox.size.width - global.dx,
        overlayBox.size.height - global.dy,
      ),
      items: entries,
    );
    _contextMenuOpen = false;
    final renderer = _renderer;
    if (renderer == null) return;
    if (selected == null) {
      renderer.dismissContextMenu();
    } else {
      renderer.activateContextMenuItem(selected);
    }
  }
}
