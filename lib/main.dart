// SPDX-License-Identifier: UNLICENSED

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'src/native_frame_renderer.dart';

void main() {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (kDebugMode && !isFlutterTest) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  final renderer = NativeFrameRenderer();
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
      title: 'Rust browser surface probe',
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

class _ProbePageState extends State<ProbePage> {
  final _addressController = TextEditingController(text: 'https://example.com');
  NativeFrameRenderer? _renderer;
  Timer? _frameTimer;
  ui.Image? _image;
  Object? _error;
  int _frameNumber = 0;
  int _framesRendered = 0;
  bool _frameInFlight = false;

  @override
  void initState() {
    super.initState();
    try {
      _renderer =
          widget.renderer ?? NativeFrameRenderer(enableCef: widget.enableCef);
      Timer.run(() {
        if (!mounted) return;
        _renderNextFrame();
        if (widget.animate) {
          _frameTimer = Timer.periodic(
            const Duration(milliseconds: 33),
            (_) => _renderNextFrame(),
          );
        }
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
      if (nextImage == null) return;
      if (!mounted) {
        nextImage.dispose();
        return;
      }
      final previousImage = _image;
      setState(() {
        _image = nextImage;
        _framesRendered += 1;
      });
      if (previousImage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previousImage.dispose();
        });
      }
    } catch (error) {
      _frameTimer?.cancel();
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      _frameInFlight = false;
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _addressController.dispose();
    _image?.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    return Scaffold(
      appBar: AppBar(title: const Text('Rust FFI browser-surface probe')),
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
                    label: '${renderer.width}×${renderer.height} RGBA',
                  ),
                if (renderer?.cefEnabled ?? false)
                  _StatusChip(
                    icon: Icons.language,
                    label: renderer!.cefFrameReady
                        ? 'CEF CPU OSR · frame ${renderer.cefFrameGeneration}'
                        : 'CEF CPU OSR · waiting for first paint',
                  ),
                _StatusChip(
                  icon: Icons.movie_filter_outlined,
                  label: 'Frames: $_framesRendered',
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
              'This frame is generated in Rust, written directly into '
              'FFI memory owned by Dart, and uploaded as a Flutter image. '
              'The procedural frame remains visible only until CEF delivers '
              'its first off-screen paint callback.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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

    if (_image case final image?) {
      return RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }

    return const Center(child: CircularProgressIndicator());
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
