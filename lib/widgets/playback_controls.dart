// lib/widgets/playback_controls.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_providers.dart';
import '../models/layout_config.dart';
import '../models/shortcut_action.dart';
import '../models/video_pair.dart';
import '../services/export_service.dart';
import 'app_notification.dart';

// ─── Theme constants ─────────────────────────────────────────────────────────

const _panelBg    = Color(0xFF0D1117);
const _pillBg     = Color(0xFF111820);
const _pillBorder = Color(0xFF1E2630);
const _cyan       = Color(0xFF4FC3F7);

// ─── Main controls widget ────────────────────────────────────────────────────

class PlaybackControls extends ConsumerStatefulWidget {
  final VoidCallback  onPrevious;
  final VoidCallback  onNext;
  final VoidCallback  onFolder;
  final VoidCallback  onLayout;
  final GlobalKey?    layoutBtnKey;
  final VoidCallback? onSaveClip;
  final VoidCallback? onCloseFolder;
  final VoidCallback? onQuit;
  final VoidCallback? onMap;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? focusRequester;

  const PlaybackControls({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onFolder,
    required this.onLayout,
    this.layoutBtnKey,
    this.onSaveClip,
    this.onCloseFolder,
    this.onQuit,
    this.onMap,
    this.onZoomIn,
    this.onZoomOut,
    this.focusRequester,
  });

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls> {
  bool _showSync = false;

  @override
  Widget build(BuildContext context) {
    final playback     = ref.watch(playbackProvider);
    final pairs        = ref.watch(videoPairListProvider);
    final index        = ref.watch(currentIndexProvider);
    final syncOffset   = ref.watch(syncOffsetProvider);
    final sortOrder    = ref.watch(sortOrderProvider);
    final layout       = ref.watch(layoutConfigProvider);
    final exportProg   = ref.watch(exportProgressProvider);
    final saveProgress = ref.watch(savingClipsProvider);
    final isSaving     = saveProgress != null;
    final notifier     = ref.read(playbackProvider.notifier);
    final sc           = ref.watch(shortcutConfigProvider);

    final hasPrev     = index > 0;
    final hasNext     = index < pairs.length - 1;
    final isLoaded    = playback.isLoaded;
    final isExporting = exportProg != null;

    final player = playback.hasFront
        ? notifier.frontPlayer
        : notifier.backPlayer;

    return Container(
      decoration: const BoxDecoration(
        color: _panelBg,
        border: Border(top: BorderSide(color: _pillBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Row 1: Transport + Seek bar ─────────────────────
        StreamBuilder<Duration>(
          stream: player.stream.position,
          builder: (_, posSnap) => StreamBuilder<Duration>(
            stream: player.stream.duration,
            builder: (_, durSnap) {
              // Use player.state as fallback — the broadcast stream
              // may have already emitted before this widget mounted.
              final pos = posSnap.data ?? player.state.position;
              final dur = durSnap.data ?? player.state.duration;
              final progress = dur.inMilliseconds > 0
                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Transport pill
                  _Pill(children: [
                    _PillIconBtn(
                      icon: Icons.skip_previous_rounded,
                      enabled: hasPrev,
                      tooltip: 'Previous (${sc.label(ShortcutAction.previousClip)})',
                      onTap: () {
                        widget.onPrevious();
                        widget.focusRequester?.call();
                      },
                    ),
                    _PillIconBtn(
                      icon: Icons.replay_10_rounded,
                      enabled: isLoaded,
                      tooltip: 'Back 10s (${sc.label(ShortcutAction.seekBackward)})',
                      onTap: () {
                        notifier.seekRelative(const Duration(seconds: -10));
                        widget.focusRequester?.call();
                      },
                    ),
                    const SizedBox(width: 2),
                    // Play / Pause
                    Tooltip(
                      message: 'Play / Pause (${sc.label(ShortcutAction.playPause)})',
                      child: GestureDetector(
                        onTap: isLoaded
                            ? () { notifier.togglePlay(); widget.focusRequester?.call(); }
                            : null,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: isLoaded
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: isLoaded ? Colors.white : Colors.white24,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    _PillIconBtn(
                      icon: Icons.forward_10_rounded,
                      enabled: isLoaded,
                      tooltip: 'Forward 10s (${sc.label(ShortcutAction.seekForward)})',
                      onTap: () {
                        notifier.seekRelative(const Duration(seconds: 10));
                        widget.focusRequester?.call();
                      },
                    ),
                    _PillIconBtn(
                      icon: Icons.skip_next_rounded,
                      enabled: hasNext,
                      tooltip: 'Next (${sc.label(ShortcutAction.nextClip)})',
                      onTap: () {
                        widget.onNext();
                        widget.focusRequester?.call();
                      },
                    ),
                  ]),
                  const SizedBox(width: 10),
                  const Text('10s',
                      style: TextStyle(color: Colors.white30, fontSize: 11)),
                  const SizedBox(width: 10),

                  // Seek bar with floating time label
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Floating time indicator
                        SizedBox(
                          height: 18,
                          child: LayoutBuilder(builder: (_, constraints) {
                            final w = constraints.maxWidth;
                            const labelW = 48.0;
                            final labelX =
                                (w * progress - labelW / 2).clamp(0.0, w - labelW);
                            return Stack(children: [
                              Positioned(
                                left: labelX,
                                child: Container(
                                  width: labelW,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _pillBg,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: _pillBorder),
                                  ),
                                  child: Text(_fmt(pos),
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontFamily: 'monospace')),
                                ),
                              ),
                            ]);
                          }),
                        ),
                        // Seek slider with tick marks
                        SizedBox(
                          height: 24,
                          child: Stack(children: [
                            Positioned.fill(
                              child: CustomPaint(painter: _TickPainter()),
                            ),
                            Positioned.fill(
                              child: ExcludeFocus(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6),
                                    overlayShape:
                                        const RoundSliderOverlayShape(
                                            overlayRadius: 10),
                                    activeTrackColor: _cyan,
                                    inactiveTrackColor:
                                        Colors.white.withValues(alpha: 0.08),
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: progress,
                                    onChanged: isLoaded
                                        ? (v) => notifier.seekTo(Duration(
                                            milliseconds:
                                                (v * dur.inMilliseconds)
                                                    .round()))
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_fmt(dur),
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 6),

        // ── Row 2: Tool pills ───────────────────────────────
        Row(children: [
          // Clip info
          if (pairs.isNotEmpty) ...[
            _Pill(children: [
              Text('${index + 1}/${pairs.length}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
              const SizedBox(width: 6),
              _statusBadge(pairs[index]),
              if (pairs[index].isLocked) ...[
                const SizedBox(width: 4),
                _pill('🔒', Colors.red.shade300),
              ],
              const SizedBox(width: 4),
              _PillIconBtn(
                icon: sortOrder == SortOrder.oldestFirst
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                enabled: true,
                tooltip: 'Toggle sort (${sc.label(ShortcutAction.toggleSort)})',
                onTap: () {
                  final next = sortOrder == SortOrder.oldestFirst
                      ? SortOrder.newestFirst
                      : SortOrder.oldestFirst;
                  ref.read(sortOrderProvider.notifier).state = next;
                  ref.read(videoPairListProvider.notifier).applySort(next);
                  ref.read(currentIndexProvider.notifier).state = 0;
                  widget.focusRequester?.call();
                },
                size: 14,
              ),
            ]),
            const SizedBox(width: 6),
          ],

          // Speed pill with presets
          _SpeedPill(
            enabled: isLoaded,
            onChanged: (speed) {
              ref.read(playbackSpeedProvider.notifier).state = speed;
              notifier.setSpeed(speed);
              widget.focusRequester?.call();
            },
          ),
          const SizedBox(width: 6),

          // Zoom
          _Pill(children: [
            _PillIconBtn(
              icon: Icons.zoom_in_rounded,
              enabled: true,
              tooltip: 'Zoom in (${sc.label(ShortcutAction.zoomIn)})',
              onTap: () => widget.onZoomIn?.call(),
              size: 16,
            ),
            _PillIconBtn(
              icon: Icons.zoom_out_rounded,
              enabled: true,
              tooltip: 'Zoom out (${sc.label(ShortcutAction.zoomOut)})',
              onTap: () => widget.onZoomOut?.call(),
              size: 16,
            ),
          ]),
          const SizedBox(width: 6),

          // Sync toggle
          GestureDetector(
            onTap: () => setState(() => _showSync = !_showSync),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _showSync ? _cyan.withValues(alpha: 0.1) : _pillBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _showSync
                      ? _cyan.withValues(alpha: 0.4)
                      : _pillBorder,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.sync_rounded,
                    size: 14, color: _showSync ? _cyan : Colors.white38),
                const SizedBox(width: 4),
                Text(
                  syncOffset == 0
                      ? 'Sync'
                      : '${syncOffset > 0 ? "+" : ""}${syncOffset}ms',
                  style: TextStyle(
                      fontSize: 11,
                      color: _showSync ? _cyan : Colors.white38),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),

          // Layout (only when both cameras present)
          if (playback.hasFront && playback.hasBack) ...[
            GestureDetector(
              key: widget.layoutBtnKey,
              onTap: widget.onLayout,
              child: _Pill(children: [
                const Icon(Icons.view_quilt_rounded,
                    size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text(_layoutLabel(layout.mode),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 6),
          ],

          // Volume controls
          if (playback.hasFront && playback.hasBack) ...[
            _VolumeBtn(
              label: 'F',
              volume: ref.watch(frontVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(frontVolumeProvider.notifier).state = v;
                notifier.setFrontVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(frontVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(frontVolumeProvider.notifier).state = next;
                notifier.setFrontVolume(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 4),
            _VolumeBtn(
              label: 'B',
              volume: ref.watch(backVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(backVolumeProvider.notifier).state = v;
                notifier.setBackVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(backVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(backVolumeProvider.notifier).state = next;
                notifier.setBackVolume(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 6),
          ] else if (playback.hasFront) ...[
            _VolumeBtn(
              label: 'Vol',
              volume: ref.watch(frontVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(frontVolumeProvider.notifier).state = v;
                notifier.setFrontVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(frontVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(frontVolumeProvider.notifier).state = next;
                notifier.setFrontVolume(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 6),
          ] else if (playback.hasBack) ...[
            _VolumeBtn(
              label: 'Vol',
              volume: ref.watch(backVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(backVolumeProvider.notifier).state = v;
                notifier.setBackVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(backVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(backVolumeProvider.notifier).state = next;
                notifier.setBackVolume(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 6),
          ],

          const Spacer(),

          // Map
          Tooltip(
            message: 'Map (${sc.label(ShortcutAction.mapSidebar)})',
            child: GestureDetector(
              onTap: () => widget.onMap?.call(),
              child: const _Pill(children: [
                Icon(Icons.map_rounded, size: 14, color: Colors.white54),
              ]),
            ),
          ),
          const SizedBox(width: 6),

          // Export (cyan highlighted)
          _ExportBtn(
            enabled: isLoaded && !isExporting,
            progress: exportProg,
            onExport: () => _doExport(context),
          ),
          const SizedBox(width: 6),

          // Save + Open Folder
          _Pill(children: [
            _SaveInline(
              isSaving: isSaving,
              progressText: saveProgress,
              onPressed: isSaving ? null : () => widget.onSaveClip?.call(),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Open folder (${sc.label(ShortcutAction.openFolder)})',
              child: GestureDetector(
                onTap: widget.onFolder,
                child: const Text('Open Folder',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ),
          ]),
        ]),

        // ── Expandable sync panel ───────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showSync
              ? _SyncPanel(syncOffsetMs: syncOffset)
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  // ── Export logic ──────────────────────────────────────────

  Future<void> _doExport(BuildContext ctx) async {
    final pair = ref.read(currentPairProvider);
    if (pair == null) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle:       'Save exported video',
      fileName:          'dashcam_${pair.id}.mp4',
      allowedExtensions: ['mp4'],
      type:              FileType.custom,
    );
    if (savePath == null) return;

    final layout     = ref.read(layoutConfigProvider);
    final syncOffset = ref.read(syncOffsetProvider);
    final pipPos     = ref.read(pipExportPositionProvider);

    ref.read(exportProgressProvider.notifier).state = 0.0;

    final ok = await ExportService.exportPair(
      pair:         pair,
      layout:       layout,
      syncOffsetMs: syncOffset,
      outputPath:   savePath,
      pipPosition:  pipPos,
      onProgress:   (p) =>
          ref.read(exportProgressProvider.notifier).state = p,
    );

    ref.read(exportProgressProvider.notifier).state = null;

    if (mounted) {
      if (ok) {
        showAppNotification(ctx, 'Exported to $savePath',
            icon: Icons.movie_creation_rounded,
            type: NotificationType.success);
        Process.run('explorer', ['/select,', savePath]);
      } else {
        showAppNotification(ctx, 'Export failed — is FFmpeg installed?',
            type: NotificationType.error);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  Widget _statusBadge(VideoPair pair) {
    if (pair.isPaired) return _pill('F+B', _cyan);
    if (pair.hasFront && !pair.hasBack && pair.source == 'local') {
      return _pill('Video', Colors.teal);
    }
    if (pair.hasFront) return _pill('F only', Colors.orange);
    return _pill('B only', Colors.purple);
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      );

  String _layoutLabel(LayoutMode m) => switch (m) {
        LayoutMode.sideBySide => 'Side-by-side',
        LayoutMode.stacked    => 'Stacked',
        LayoutMode.pip        => 'PIP',
        LayoutMode.frontOnly  => 'Front only',
        LayoutMode.backOnly   => 'Back only',
      };

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Pill container ──────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final List<Widget> children;
  const _Pill({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _pillBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _pillBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}

// ─── Pill icon button ────────────────────────────────────────────────────────

class _PillIconBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  const _PillIconBtn({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    this.onTap,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: ExcludeFocus(
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(icon,
                  size: size,
                  color: enabled ? Colors.white70 : Colors.white24),
            ),
          ),
        ),
      );
}

// ─── Tick mark painter for seek bar ──────────────────────────────────────────

class _TickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final count = (size.width / 12).floor();
    if (count <= 0) return;
    final step = size.width / count;
    final cy = size.height / 2;
    for (var i = 0; i <= count; i++) {
      final x = i * step;
      final isMajor = i % 5 == 0;
      final h = isMajor ? 6.0 : 3.0;
      canvas.drawLine(Offset(x, cy - h), Offset(x, cy + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Export button (cyan highlighted) ────────────────────────────────────────

class _ExportBtn extends ConsumerWidget {
  final bool    enabled;
  final double? progress;
  final VoidCallback onExport;

  const _ExportBtn({
    required this.enabled,
    required this.progress,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExporting = progress != null;
    final sc = ref.watch(shortcutConfigProvider);

    return Tooltip(
      message: 'Export current clip (${sc.label(ShortcutAction.exportVideo)})',
      child: GestureDetector(
        onTap: enabled ? onExport : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: enabled
                ? _cyan.withValues(alpha: 0.15)
                : _pillBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? _cyan.withValues(alpha: 0.5)
                  : _pillBorder,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isExporting)
              SizedBox(
                width: 13, height: 13,
                child: CircularProgressIndicator(
                  value:       progress,
                  strokeWidth: 1.5,
                  color:       _cyan,
                ),
              )
            else
              Icon(Icons.movie_creation_outlined,
                  size: 14, color: enabled ? _cyan : Colors.white24),
            const SizedBox(width: 5),
            Text(
              isExporting
                  ? '${((progress ?? 0) * 100).round()}%'
                  : 'Export',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled ? _cyan : Colors.white24,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Save inline button ─────────────────────────────────────────────────────

class _SaveInline extends ConsumerWidget {
  final bool isSaving;
  final String? progressText;
  final VoidCallback? onPressed;
  const _SaveInline({
    required this.isSaving,
    this.progressText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(shortcutConfigProvider);
    return Tooltip(
      message: isSaving
          ? 'Saving...'
          : 'Save clip files (${sc.label(ShortcutAction.saveClips)})',
      child: GestureDetector(
        onTap: onPressed,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isSaving)
            const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: _cyan),
            )
          else
            Icon(Icons.save_alt_rounded,
                size: 13,
                color: onPressed != null ? Colors.white54 : Colors.white24),
          const SizedBox(width: 4),
          Text(
            isSaving ? (progressText ?? 'Saving...') : 'Save Clip',
            style: TextStyle(
              fontSize: 11,
              color: isSaving
                  ? _cyan
                  : onPressed != null
                      ? Colors.white54
                      : Colors.white24,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Speed pill with presets ─────────────────────────────────────────────────

class _SpeedPill extends ConsumerWidget {
  final bool enabled;
  final ValueChanged<double> onChanged;
  const _SpeedPill({required this.enabled, required this.onChanged});

  static const _presets = [0.5, 1.0, 2.0, 5.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    final sc    = ref.watch(shortcutConfigProvider);

    return PopupMenuButton<double>(
      onSelected: onChanged,
      enabled: enabled,
      tooltip: 'All speeds (${sc.label(ShortcutAction.speedDown)} / ${sc.label(ShortcutAction.speedUp)})',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: const Color(0xFF161D26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(0, -200),
      itemBuilder: (_) => [
        for (final s in playbackSpeeds)
          PopupMenuItem(
            value: s,
            height: 34,
            child: Row(children: [
              if (s == speed)
                const Icon(Icons.check_rounded, size: 14, color: _cyan)
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Text(
                s == s.roundToDouble() ? '${s.round()}x' : '${s}x',
                style: TextStyle(
                  fontSize: 12,
                  color: s == speed ? _cyan : Colors.white60,
                  fontWeight: s == speed ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
      ],
      child: _Pill(children: [
        const Text('Speed',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        for (final s in _presets) ...[
          _SpeedPresetChip(
            speed: s,
            active: speed == s,
            enabled: enabled,
            onTap: () => onChanged(s),
          ),
          if (s != _presets.last) const SizedBox(width: 2),
        ],
        // Show current speed if it's not a preset
        if (!_presets.contains(speed)) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _cyan.withValues(alpha: 0.5)),
            ),
            child: Text(
              speed == speed.roundToDouble()
                  ? '${speed.round()}x'
                  : '${speed}x',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _cyan),
            ),
          ),
        ],
      ]),
    );
  }
}

class _SpeedPresetChip extends StatelessWidget {
  final double speed;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _SpeedPresetChip({
    required this.speed,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: active ? _cyan.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active
                  ? _cyan.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            speed == speed.roundToDouble()
                ? '${speed.round()}x'
                : '${speed}x',
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active
                  ? _cyan
                  : (enabled ? Colors.white54 : Colors.white24),
            ),
          ),
        ),
      );
}

// ─── Sync panel ──────────────────────────────────────────────────────────────

class _SyncPanel extends ConsumerWidget {
  final int syncOffsetMs;
  const _SyncPanel({required this.syncOffsetMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(color: _pillBorder, height: 10),
        Row(children: [
          const Text('Sync offset',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const Spacer(),
          Text(
            '${syncOffsetMs > 0 ? "+" : ""}$syncOffsetMs ms  '
            '(${syncOffsetMs > 0 ? "front ahead" : syncOffsetMs < 0 ? "back ahead" : "aligned"})',
            style: const TextStyle(color: _cyan, fontSize: 11),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              ref.read(syncOffsetProvider.notifier).state = 0;
              ref.read(playbackProvider.notifier).applySyncOffset(0);
            },
            child: const Text('Reset',
                style: TextStyle(color: Colors.white30, fontSize: 10)),
          ),
        ]),
        ExcludeFocus(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: _cyan,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
            ),
            child: Slider(
              min: -5000, max: 5000, divisions: 200,
              value:       syncOffsetMs.toDouble(),
              onChanged:   (v) =>
                  ref.read(syncOffsetProvider.notifier).state = v.round(),
              onChangeEnd: (v) =>
                  ref.read(playbackProvider.notifier).applySyncOffset(v.round()),
            ),
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('-5 s',
                style: TextStyle(color: Colors.white24, fontSize: 9)),
            Text('aligned',
                style: TextStyle(color: Colors.white24, fontSize: 9)),
            Text('+5 s',
                style: TextStyle(color: Colors.white24, fontSize: 9)),
          ],
        ),
      ]),
    );
  }
}

// ─── Volume button with popup slider ─────────────────────────────────────────

class _VolumeBtn extends StatefulWidget {
  final String label;
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggle;
  const _VolumeBtn({
    required this.label,
    required this.volume,
    required this.onVolumeChanged,
    required this.onMuteToggle,
  });

  @override
  State<_VolumeBtn> createState() => _VolumeBtnState();
}

class _VolumeBtnState extends State<_VolumeBtn> {
  bool _open = false;

  bool get _muted => widget.volume <= 0;

  IconData get _icon {
    if (_muted) return Icons.volume_off_rounded;
    if (widget.volume < 50) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: _toggle,
      onLongPress: widget.onMuteToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _muted ? Colors.red.withValues(alpha: 0.12) : _pillBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _muted
                ? Colors.red.withValues(alpha: 0.4)
                : _pillBorder,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_icon,
              size: 13,
              color: _muted ? Colors.redAccent : Colors.white54),
          const SizedBox(width: 4),
          Text(widget.label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _muted ? Colors.redAccent : Colors.white54)),
        ]),
      ),
    );

    // Stack with Clip.none lets the popup overflow above without
    // shifting layout. The non-positioned button child sizes the Stack.
    return TapRegion(
      groupId: 'vol_${widget.label}',
      onTapOutside: (_) {
        if (_open) setState(() => _open = false);
      },
      child: SizedBox(
        height: 27,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            button,
            if (_open)
              Positioned(
                bottom: 31,
                left: 0,
                child: Container(
                  width: 40,
                  height: 130,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161D26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _pillBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(children: [
                    Text('${widget.volume.round()}',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 96,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: ExcludeFocus(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              overlayShape:
                                  const RoundSliderOverlayShape(
                                      overlayRadius: 10),
                              activeTrackColor:
                                  _muted ? Colors.redAccent : _cyan,
                              inactiveTrackColor: Colors.white12,
                              thumbColor:
                                  _muted ? Colors.redAccent : _cyan,
                              overlayColor:
                                  _cyan.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: widget.volume,
                              min: 0,
                              max: 100,
                              onChanged: widget.onVolumeChanged,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
