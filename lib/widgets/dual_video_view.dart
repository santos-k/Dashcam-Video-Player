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

  // PIP drag state — offset from top-left of the video area
  Offset _pipOffset     = const Offset(-1, -1); // -1 = not placed yet, use default
  double _pipWidth      = 280;
  double _pipHeight     = 158;
  bool   _isDragging    = false;

  static const double _minPipW = 160;
  static const double _maxPipW = 600;

  @override
  void initState() {
    super.initState();
    final n = ref.read(playbackProvider.notifier);
    _frontController = VideoController(n.frontPlayer);
    _backController  = VideoController(n.backPlayer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ref.listenManual(pipResetProvider, (_, __) {
      setState(() => _pipOffset = const Offset(-1, -1));
    });
  }

  Offset _defaultOffset(BoxConstraints bc, LayoutConfig layout) {
    // Resolve grid position from pipHAlign / pipVAlign
    double x, y;
    const margin = 16.0;

    switch (layout.pipHAlign) {
      case PipHAlign.left:   x = margin; break;
      case PipHAlign.center: x = (bc.maxWidth  - _pipWidth)  / 2; break;
      case PipHAlign.right:  x = bc.maxWidth  - _pipWidth  - margin; break;
    }
    switch (layout.pipVAlign) {
      case PipVAlign.top:    y = margin; break;
      case PipVAlign.center: y = (bc.maxHeight - _pipHeight) / 2; break;
      case PipVAlign.bottom: y = bc.maxHeight - _pipHeight - margin; break;
    }
    return Offset(x, y);
  }

  Offset _clamp(Offset o, BoxConstraints bc) => Offset(
    o.dx.clamp(0, bc.maxWidth  - _pipWidth),
    o.dy.clamp(0, bc.maxHeight - _pipHeight),
  );

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final layout   = ref.watch(layoutConfigProvider);

    if (!playback.isLoaded) return const SizedBox.shrink();

    // Single video modes
    if (playback.hasFront && !playback.hasBack) {
      return _VideoPane(controller: _frontController, label: 'FRONT');
    }
    if (playback.hasBack && !playback.hasFront) {
      return _VideoPane(controller: _backController, label: 'BACK');
    }
    if (!playback.hasFront && !playback.hasBack) {
      return const Center(
        child: Text('No video', style: TextStyle(color: Colors.white38)));
    }

    final front = _VideoPane(controller: _frontController, label: 'FRONT');
    final back  = _VideoPane(controller: _backController,  label: 'BACK');

    switch (layout.mode) {
      case LayoutMode.sideBySide:
        return Row(children: [
          Expanded(child: front),
          const SizedBox(width: 2),
          Expanded(child: back),
        ]);

      case LayoutMode.stacked:
        return Column(children: [
          Expanded(child: front),
          const SizedBox(height: 2),
          Expanded(child: back),
        ]);

      case LayoutMode.pip:
        final mainVideo = layout.pipPrimary == PipPrimary.front ? front : back;
        final pipVideo  = layout.pipPrimary == PipPrimary.front ? back  : front;
        final pipLabel  = layout.pipPrimary == PipPrimary.front ? 'BACK' : 'FRONT';

        return LayoutBuilder(builder: (context, bc) {
          // First time or after alignment change: snap to grid position
          if (_pipOffset.dx < 0) {
            _pipOffset = _defaultOffset(bc, layout);
          }

          return Stack(clipBehavior: Clip.hardEdge, children: [
            // Main video fills everything
            Positioned.fill(child: mainVideo),

            // Draggable PIP overlay
            Positioned(
              left: _pipOffset.dx,
              top:  _pipOffset.dy,
              child: GestureDetector(
                // Drag to reposition
                onPanUpdate: (d) {
                  setState(() {
                    _isDragging = true;
                    _pipOffset  = _clamp(
                      _pipOffset + d.delta, bc);
                  });
                },
                onPanEnd: (_) => setState(() => _isDragging = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width:  _pipWidth,
                  height: _pipHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isDragging
                          ? const Color(0xFF4FC3F7)
                          : Colors.white24,
                      width: _isDragging ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:   Colors.black.withOpacity(0.6),
                        blurRadius: 12, spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(children: [
                      // PIP video
                      pipVideo,

                      // no label in PIP overlay

                      // Drag hint icon
                      if (!_isDragging)
                        Positioned(
                          top: 6, right: 6,
                          child: Icon(Icons.open_with_rounded,
                            color: Colors.white38, size: 14),
                        ),
                    ]),
                  ),
                ),
              ),
            ),

            // Resize handle (bottom-right corner)
            Positioned(
              left: _pipOffset.dx + _pipWidth  - 20,
              top:  _pipOffset.dy + _pipHeight - 20,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    _pipWidth  = (_pipWidth  + d.delta.dx)
                        .clamp(_minPipW, _maxPipW);
                    _pipHeight = _pipWidth * (9 / 16); // maintain 16:9
                    _pipOffset = _clamp(_pipOffset, bc);
                  });
                },
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.zoom_out_map_rounded,
                    color: Colors.white54, size: 14),
                ),
              ),
            ),
          ]);
        });
    }
  }
}

// ─── Video pane ───────────────────────────────────────────────────────────────

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
          controller: controller,
          controls:   NoVideoControls,
          fit:        BoxFit.contain,
        ),
      ),
      // labels removed — camera identity shown in controls bar only
    ]);
  }
}