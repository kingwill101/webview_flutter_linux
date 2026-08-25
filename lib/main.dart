// SPDX-License-Identifier: UNLICENSED

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'src/native_frame_renderer.dart';

void main() {
  runApp(const ProbeApp());
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key, this.animate = true});

  final bool animate;

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
      home: ProbePage(animate: animate),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key, required this.animate});

  final bool animate;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
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
      _renderer = NativeFrameRenderer();
      _renderNextFrame();
      if (widget.animate) {
        _frameTimer = Timer.periodic(
          const Duration(milliseconds: 33),
          (_) => _renderNextFrame(),
        );
      }
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
                _StatusChip(
                  icon: Icons.movie_filter_outlined,
                  label: 'Frames: $_framesRendered',
                ),
              ],
            ),
            const SizedBox(height: 18),
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
              'CEF will replace the procedural renderer after this boundary '
              'is proven stable.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
