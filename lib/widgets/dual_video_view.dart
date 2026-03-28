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
  static const double _pipMargin = 4.0;

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

  /// Calculate the actual visible video rect within the container
  /// (accounting for BoxFit.contain letterboxing).
  Rect _videoRect(BoxConstraints bc, LayoutConfig layout) {
    final mainCtrl = layout.pipPrimary == PipPrimary.front
        ? _frontController : _backController;
    final vw = mainCtrl.player.state.width;
    final vh = mainCtrl.player.state.height;
    if (vw == null || vh == null || vw == 0 || vh == 0) {
      // Fallback to full container if video dimensions unknown
      return Rect.fromLTWH(0, 0, bc.maxWidth, bc.maxHeight);
    }

    final containerAR = bc.maxWidth / bc.maxHeight;
    final videoAR     = vw / vh;

    double displayW, displayH, offsetX, offsetY;
    if (videoAR > containerAR) {
      // Video is wider — black bars top/bottom
      displayW = bc.maxWidth;
      displayH = bc.maxWidth / videoAR;
      offsetX  = 0;
      offsetY  = (bc.maxHeight - displayH) / 2;
    } else {
      // Video is taller — black bars left/right
      displayH = bc.maxHeight;
      displayW = bc.maxHeight * videoAR;
      offsetX  = (bc.maxWidth - displayW) / 2;
      offsetY  = 0;
    }
    return Rect.fromLTWH(offsetX, offsetY, displayW, displayH);
  }

  Offset _defaultOffset(Rect videoRect, LayoutConfig layout) {
    double x, y;
    const margin = 16.0;

    switch (layout.pipHAlign) {
      case PipHAlign.left:   x = videoRect.left + margin; break;
      case PipHAlign.center: x = videoRect.left + (videoRect.width  - _pipWidth)  / 2; break;
      case PipHAlign.right:  x = videoRect.right - _pipWidth  - margin; break;
    }
    switch (layout.pipVAlign) {
      case PipVAlign.top:    y = videoRect.top + margin; break;
      case PipVAlign.center: y = videoRect.top + (videoRect.height - _pipHeight) / 2; break;
      case PipVAlign.bottom: y = videoRect.bottom - _pipHeight - margin; break;
    }
    return Offset(x, y);
  }

  Offset _clamp(Offset o, Rect videoRect) => Offset(
    o.dx.clamp(videoRect.left + _pipMargin, videoRect.right  - _pipWidth  - _pipMargin),
    o.dy.clamp(videoRect.top  + _pipMargin, videoRect.bottom - _pipHeight - _pipMargin),
  );

  /// Store fractional PIP position for export.
  void _updateExportPosition(Rect videoRect) {
    final rangeX = videoRect.width  - _pipWidth  - _pipMargin * 2;
    final rangeY = videoRect.height - _pipHeight - _pipMargin * 2;
    if (rangeX <= 0 || rangeY <= 0) return;
    final fx = (_pipOffset.dx - videoRect.left - _pipMargin) / rangeX;
    final fy = (_pipOffset.dy - videoRect.top  - _pipMargin) / rangeY;
    ref.read(pipExportPositionProvider.notifier).state =
        (fx.clamp(0.0, 1.0), fy.clamp(0.0, 1.0));
  }

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

        return LayoutBuilder(builder: (context, bc) {
          final vRect = _videoRect(bc, layout);

          // First time or after alignment change: snap to grid position
          if (_pipOffset.dx < 0) {
            _pipOffset = _defaultOffset(vRect, layout);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref.read(pipExportPositionProvider.notifier).state = (-1.0, -1.0);
              }
            });
          }

          // Re-clamp in case container/video size changed
          _pipOffset = _clamp(_pipOffset, vRect);

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
                    _pipOffset  = _clamp(_pipOffset + d.delta, vRect);
                  });
                },
                onPanEnd: (_) {
                  setState(() => _isDragging = false);
                  _updateExportPosition(vRect);
                },
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
                        color:   Colors.black.withValues(alpha: 0.6),
                        blurRadius: 12, spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(children: [
                      // PIP video
                      pipVideo,

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
                    _pipOffset = _clamp(_pipOffset, vRect);
                  });
                },
                onPanEnd: (_) => _updateExportPosition(vRect),
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
