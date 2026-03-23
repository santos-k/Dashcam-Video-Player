// lib/widgets/dual_video_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/layout_config.dart';
import '../providers/app_providers.dart';

class DualVideoView extends ConsumerStatefulWidget {
  const DualVideoView({super.key});

  @override
  ConsumerState<DualVideoView> createState() => _DualVideoViewState();
}

class _DualVideoViewState extends ConsumerState<DualVideoView> {
  late VideoController _frontController;
  late VideoController _backController;

  @override
  void initState() {
    super.initState();
    final notifier      = ref.read(playbackProvider.notifier);
    _frontController    = VideoController(notifier.frontPlayer);
    _backController     = VideoController(notifier.backPlayer);
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final layout   = ref.watch(layoutConfigProvider);

    if (!playback.isLoaded) return const SizedBox.shrink();

    // Single video
    if (playback.hasFront && !playback.hasBack) {
      return _VideoPane(controller: _frontController, label: 'FRONT');
    }
    if (playback.hasBack && !playback.hasFront) {
      return _VideoPane(controller: _backController, label: 'BACK');
    }
    if (!playback.hasFront && !playback.hasBack) {
      return const Center(
        child: Text('No video', style: TextStyle(color: Colors.white38)),
      );
    }

    // Dual video
    final front = _VideoPane(controller: _frontController, label: 'FRONT');
    final back  = _VideoPane(controller: _backController,  label: 'BACK');

    return switch (layout.mode) {
      LayoutMode.sideBySide => Row(children: [
          Expanded(child: front),
          const SizedBox(width: 2),
          Expanded(child: back),
        ]),
      LayoutMode.stacked => Column(children: [
          Expanded(child: front),
          const SizedBox(height: 2),
          Expanded(child: back),
        ]),
      LayoutMode.pip => _PipView(
          front:   front,
          back:    back,
          primary: layout.pipPrimary,
          corner:  layout.pipCorner,
        ),
    };
  }
}

// ─── PIP layout ──────────────────────────────────────────────────────────────

class _PipView extends StatelessWidget {
  final Widget front;
  final Widget back;
  final PipPrimary primary;
  final PipCorner  corner;
  const _PipView({
    required this.front, required this.back,
    required this.primary, required this.corner,
  });

  @override
  Widget build(BuildContext context) {
    final main     = primary == PipPrimary.front ? front : back;
    final pip      = primary == PipPrimary.front ? back  : front;
    final pipLabel = primary == PipPrimary.front ? 'BACK' : 'FRONT';

    return Stack(children: [
      Positioned.fill(child: main),
      Positioned(
        top:    _top(corner), bottom: _bottom(corner),
        left:   _left(corner), right:  _right(corner),
        child: SizedBox(
          width: 180, height: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(children: [
              pip,
              Positioned(
                bottom: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(pipLabel,
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 9,
                      fontWeight: FontWeight.w600, letterSpacing: 0.5,
                    )),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  double? _top(PipCorner c) =>
      (c == PipCorner.topLeft    || c == PipCorner.topRight)    ? 16 : null;
  double? _bottom(PipCorner c) =>
      (c == PipCorner.bottomLeft || c == PipCorner.bottomRight) ? 16 : null;
  double? _left(PipCorner c) =>
      (c == PipCorner.topLeft    || c == PipCorner.bottomLeft)  ? 16 : null;
  double? _right(PipCorner c) =>
      (c == PipCorner.topRight   || c == PipCorner.bottomRight) ? 16 : null;
}

// ─── Single video pane ────────────────────────────────────────────────────────

class _VideoPane extends StatelessWidget {
  final VideoController controller;
  final String label;
  const _VideoPane({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(color: Colors.black),
      Center(
        child: Video(
          controller:    controller,
          controls:      NoVideoControls, // we have our own controls
          fit:           BoxFit.contain,
        ),
      ),
      Positioned(
        top: 8, left: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
            style: const TextStyle(
              color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2,
            )),
        ),
      ),
    ]);
  }
}