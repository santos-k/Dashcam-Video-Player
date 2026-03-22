// lib/widgets/dual_video_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../models/layout_config.dart';
import '../providers/app_providers.dart';

class DualVideoView extends ConsumerWidget {
  const DualVideoView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final layout   = ref.watch(layoutConfigProvider);

    if (!playback.isLoaded ||
        playback.frontController == null ||
        playback.backController  == null) {
      return const Center(
        child: Text('No video loaded', style: TextStyle(color: Colors.white54)),
      );
    }

    final front = _VideoPane(
      controller: playback.frontController!,
      label: 'FRONT',
    );
    final back = _VideoPane(
      controller: playback.backController!,
      label: 'BACK',
    );

    return switch (layout.mode) {
      LayoutMode.sideBySide => _SideBySide(front: front, back: back),
      LayoutMode.stacked    => _Stacked(front: front, back: back),
      LayoutMode.pip        => _PipView(
          front:   front,
          back:    back,
          primary: layout.pipPrimary,
          corner:  layout.pipCorner,
        ),
    };
  }
}

// ─── Side by side ───────────────────────────────────────────────────────────

class _SideBySide extends StatelessWidget {
  final Widget front;
  final Widget back;
  const _SideBySide({required this.front, required this.back});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: front),
        const SizedBox(width: 2),
        Expanded(child: back),
      ],
    );
  }
}

// ─── Stacked ─────────────────────────────────────────────────────────────────

class _Stacked extends StatelessWidget {
  final Widget front;
  final Widget back;
  const _Stacked({required this.front, required this.back});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: front),
        const SizedBox(height: 2),
        Expanded(child: back),
      ],
    );
  }
}

// ─── PIP ─────────────────────────────────────────────────────────────────────

class _PipView extends StatelessWidget {
  final Widget front;
  final Widget back;
  final PipPrimary primary;
  final PipCorner  corner;

  const _PipView({
    required this.front,
    required this.back,
    required this.primary,
    required this.corner,
  });

  @override
  Widget build(BuildContext context) {
    final mainVideo = primary == PipPrimary.front ? front : back;
    final pipVideo  = primary == PipPrimary.front ? back  : front;

    return Stack(
      children: [
        Positioned.fill(child: mainVideo),
        Positioned(
          top:    _top(corner),
          bottom: _bottom(corner),
          left:   _left(corner),
          right:  _right(corner),
          child: SizedBox(
            width:  180,
            height: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  pipVideo,
                  // Drag handle hint
                  Positioned(
                    bottom: 4,
                    right:  4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        primary == PipPrimary.front ? 'BACK' : 'FRONT',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double? _top(PipCorner c) =>
      (c == PipCorner.topLeft || c == PipCorner.topRight) ? 16 : null;
  double? _bottom(PipCorner c) =>
      (c == PipCorner.bottomLeft || c == PipCorner.bottomRight) ? 16 : null;
  double? _left(PipCorner c) =>
      (c == PipCorner.topLeft || c == PipCorner.bottomLeft) ? 16 : null;
  double? _right(PipCorner c) =>
      (c == PipCorner.topRight || c == PipCorner.bottomRight) ? 16 : null;
}

// ─── Individual video pane ────────────────────────────────────────────────────

class _VideoPane extends StatelessWidget {
  final VideoPlayerController controller;
  final String label;

  const _VideoPane({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Black background for letterboxing
        Container(color: Colors.black),
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.isInitialized
                ? controller.value.aspectRatio
                : 16 / 9,
            child: VideoPlayer(controller),
          ),
        ),
        // Camera label badge
        Positioned(
          top:  8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}