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
  final VoidCallback? onZoomReset;
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
    this.onZoomReset,
    this.focusRequester,
  });

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls> {
  bool _showSync = false;

  @override
  Widget build(BuildContext context) {
    final playback    = ref.watch(playbackProvider);
    final pairs       = ref.watch(videoPairListProvider);
    final index       = ref.watch(currentIndexProvider);
    final syncOffset  = ref.watch(syncOffsetProvider);
    final sortOrder   = ref.watch(sortOrderProvider);
    final layout      = ref.watch(layoutConfigProvider);
    final exportProg  = ref.watch(exportProgressProvider);
    // Volume providers (kept for reference in controls below)
    // final frontVolume = ref.watch(frontVolumeProvider);
    // final backVolume  = ref.watch(backVolumeProvider);
    final saveProgress = ref.watch(savingClipsProvider);
    final isSaving     = saveProgress != null;
    final notifier    = ref.read(playbackProvider.notifier);
    final sc          = ref.watch(shortcutConfigProvider);

    final hasPrev  = index > 0;
    final hasNext  = index < pairs.length - 1;
    final isLoaded = playback.isLoaded;
    final isExporting = exportProg != null;

    final player = playback.hasFront
        ? notifier.frontPlayer
        : notifier.backPlayer;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // ── Row 1: clip info + tools ──────────────────────
        Row(children: [
          // Clip counter
          if (pairs.isNotEmpty) ...[
            Text('${index + 1} / ${pairs.length}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(width: 6),
            _statusBadge(pairs[index]),
            if (pairs[index].isLocked) ...[
              const SizedBox(width: 4),
              _pill('🔒', Colors.red.shade300),
            ],
          ],
          const Spacer(),

          // Sort cycle
          _ToolBtn(
            icon: Icons.sort_rounded,
            label: _sortLabel(sortOrder),
            tooltip: 'Cycle sort (${sc.label(ShortcutAction.toggleSort)})',
            onPressed: () {
              final values = SortOrder.values;
              final next = values[(sortOrder.index + 1) % values.length];
              ref.read(sortOrderProvider.notifier).state = next;
              final notifier = ref.read(videoPairListProvider.notifier);
              notifier.setDurationCache(ref.read(clipDurationCacheProvider));
              notifier.applySort(next);
              ref.read(currentIndexProvider.notifier).state = 0;
              widget.focusRequester?.call();
            },
          ),
          const SizedBox(width: 4),

          // Layout — only useful when both cameras are present
          if (playback.hasFront && playback.hasBack)
            _ToolBtn(
              key:     widget.layoutBtnKey,
              icon:    Icons.view_quilt_rounded,
              label:   _layoutLabel(layout.mode),
              tooltip: 'Change layout (${sc.label(ShortcutAction.layoutPopup)})',
              onPressed: widget.onLayout,
            ),
          const SizedBox(width: 4),

          // Open folder
          _ToolBtn(
            icon:    Icons.folder_open_rounded,
            label:   'Open',
            tooltip: 'Open dashcam folder (${sc.label(ShortcutAction.openFolder)})',
            onPressed: widget.onFolder,
          ),
          const SizedBox(width: 4),

          // Map
          _ToolBtn(
            icon:    Icons.map_rounded,
            label:   'Map',
            tooltip: 'Show GPS location on map (${sc.label(ShortcutAction.mapSidebar)})',
            onPressed: () {
              widget.onMap?.call();
            },
          ),
          const SizedBox(width: 4),

          // Export single clip
          _ExportBtn(
            enabled:    isLoaded && !isExporting,
            progress:   exportProg,
            onExport:   () => _doExport(context),
          ),
          const SizedBox(width: 4),

          // Save current clip
          _SaveBtn(
            isSaving: isSaving,
            progressText: saveProgress,
            onPressed: isSaving ? null : () {
              widget.onSaveClip?.call();
            },
          ),
          const SizedBox(width: 4),

          // Close folder
          _ToolBtn(
            icon:    Icons.folder_off_rounded,
            label:   'Close Folder',
            tooltip: 'Close loaded folder (${sc.label(ShortcutAction.closeFolder)})',
            onPressed: () {
              widget.onCloseFolder?.call();
            },
          ),
          const SizedBox(width: 4),

          // Quit
          _ToolBtn(
            icon:    Icons.power_settings_new_rounded,
            label:   'Quit',
            tooltip: 'Quit application (${sc.label(ShortcutAction.quit)})',
            onPressed: () {
              widget.onQuit?.call();
            },
          ),
        ]),

        const SizedBox(height: 2),

        // ── Row 2: seek bar ───────────────────────────────
        StreamBuilder<Duration>(
          stream: player.stream.position,
          builder: (_, posSnap) => StreamBuilder<Duration>(
            stream: player.stream.duration,
            builder: (_, durSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final dur = durSnap.data ?? Duration.zero;
              final progress = dur.inMilliseconds > 0
                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0;
              return Row(children: [
                Text(_fmt(pos),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
                Expanded(
                  child: ExcludeFocus(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight:  3,
                        thumbShape:   const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value:     progress,
                        onChanged: isLoaded
                            ? (v) => notifier.seekTo(
                                Duration(milliseconds: (v * dur.inMilliseconds).round()))
                            : null,
                        activeColor:   const Color(0xFF4FC3F7),
                        inactiveColor: Colors.white12,
                        thumbColor:    Colors.white,
                      ),
                    ),
                  ),
                ),
                Text(_fmt(dur),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]);
            },
          ),
        ),

        // ── Row 3: transport ──────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _NavBtn(icon: Icons.skip_previous_rounded,
            enabled: hasPrev, tooltip: 'Previous (${sc.label(ShortcutAction.previousClip)})',
            onPressed: () { widget.onPrevious(); widget.focusRequester?.call(); }),
          _NavBtn(icon: Icons.replay_10_rounded,
            enabled: isLoaded, tooltip: 'Back 10s (${sc.label(ShortcutAction.seekBackward)})',
            onPressed: () {
              notifier.seekRelative(const Duration(seconds: -10));
              widget.focusRequester?.call();
            }),

          const SizedBox(width: 8),
          // Play/Pause big button
          Tooltip(
            message: 'Play / Pause (${sc.label(ShortcutAction.playPause)})',
            child: GestureDetector(
            onTap: isLoaded ? () { notifier.togglePlay(); widget.focusRequester?.call(); } : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: isLoaded ? const Color(0xFF4FC3F7) : Colors.white12,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(
                playback.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: isLoaded ? Colors.black : Colors.white24,
                size: 26,
              ),
            ),
          ),
          ),
          const SizedBox(width: 8),

          _NavBtn(icon: Icons.forward_10_rounded,
            enabled: isLoaded, tooltip: 'Forward 10s (${sc.label(ShortcutAction.seekForward)})',
            onPressed: () {
              notifier.seekRelative(const Duration(seconds: 10));
              widget.focusRequester?.call();
            }),
          _NavBtn(icon: Icons.skip_next_rounded,
            enabled: hasNext, tooltip: 'Next (${sc.label(ShortcutAction.nextClip)})',
            onPressed: () { widget.onNext(); widget.focusRequester?.call(); }),

          const SizedBox(width: 12),

          // Speed control
          _SpeedBtn(
            enabled: isLoaded,
            onChanged: (speed) {
              ref.read(playbackSpeedProvider.notifier).state = speed;
              notifier.setSpeed(speed);
              widget.focusRequester?.call();
            },
          ),

          const SizedBox(width: 8),

          // Zoom controls
          _NavBtn(icon: Icons.zoom_in_rounded,
            enabled: isLoaded,
            tooltip: 'Zoom in (${sc.label(ShortcutAction.zoomIn)})',
            onPressed: () => widget.onZoomIn?.call()),
          _NavBtn(icon: Icons.zoom_out_rounded,
            enabled: isLoaded,
            tooltip: 'Zoom out (${sc.label(ShortcutAction.zoomOut)})',
            onPressed: () => widget.onZoomOut?.call()),
          _NavBtn(icon: Icons.fit_screen_rounded,
            enabled: isLoaded,
            tooltip: 'Reset zoom (${sc.label(ShortcutAction.zoomReset)})',
            onPressed: () => widget.onZoomReset?.call()),

          const SizedBox(width: 4),

          // Volume controls
          if (playback.hasFront && playback.hasBack) ...[
            _VolumeBtn(
              label: 'F',
              volume: ref.watch(frontVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(frontVolumeProvider.notifier).state = v;
                ref.read(playbackProvider.notifier).setFrontVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(frontVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(frontVolumeProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setFrontVolume(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 2),
            _VolumeBtn(
              label: 'B',
              volume: ref.watch(backVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(backVolumeProvider.notifier).state = v;
                ref.read(playbackProvider.notifier).setBackVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(backVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(backVolumeProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setBackVolume(next);
                widget.focusRequester?.call();
              },
            ),
          ] else if (playback.hasFront) ...[
            _VolumeBtn(
              label: 'Vol',
              volume: ref.watch(frontVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(frontVolumeProvider.notifier).state = v;
                ref.read(playbackProvider.notifier).setFrontVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(frontVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(frontVolumeProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setFrontVolume(next);
                widget.focusRequester?.call();
              },
            ),
          ] else if (playback.hasBack) ...[
            _VolumeBtn(
              label: 'Vol',
              volume: ref.watch(backVolumeProvider),
              onVolumeChanged: (v) {
                ref.read(backVolumeProvider.notifier).state = v;
                ref.read(playbackProvider.notifier).setBackVolume(v);
              },
              onMuteToggle: () {
                final cur = ref.read(backVolumeProvider);
                final next = cur > 0 ? 0.0 : 100.0;
                ref.read(backVolumeProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setBackVolume(next);
                widget.focusRequester?.call();
              },
            ),
          ],

          const Spacer(),

          // Sync toggle
          GestureDetector(
            onTap: () => setState(() => _showSync = !_showSync),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _showSync
                    ? const Color(0xFF4FC3F7).withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _showSync
                      ? const Color(0xFF4FC3F7).withValues(alpha: 0.5)
                      : Colors.white12,
                ),
              ),
              child: Row(children: [
                Icon(Icons.sync_rounded,
                  size: 14,
                  color: _showSync ? const Color(0xFF4FC3F7) : Colors.white38),
                const SizedBox(width: 4),
                Text(
                  syncOffset == 0
                      ? 'Sync'
                      : '${syncOffset > 0 ? "+" : ""}${syncOffset}ms',
                  style: TextStyle(
                    fontSize: 11,
                    color: _showSync ? const Color(0xFF4FC3F7) : Colors.white38,
                  ),
                ),
              ]),
            ),
          ),
        ]),

        // ── Sync slider (expandable) ───────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showSync ? _SyncPanel(syncOffsetMs: syncOffset) : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Future<void> _doExport(BuildContext ctx) async {
    final pair = ref.read(currentPairProvider);
    if (pair == null) return;

    // Ask for output path
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle:   'Save exported video',
      fileName:      'dashcam_${pair.id}.mp4',
      allowedExtensions: ['mp4'],
      type: FileType.custom,
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
            icon: Icons.movie_creation_rounded, type: NotificationType.success);
        Process.run('explorer', ['/select,', savePath]);
      } else {
        showAppNotification(ctx, 'Export failed — is FFmpeg installed?',
            type: NotificationType.error);
      }
    }
  }

  Widget _statusBadge(VideoPair pair) {
    if (pair.isPaired) return _pill('F+B', const Color(0xFF4FC3F7));
    if (pair.hasFront && !pair.hasBack && pair.source == 'local') {
      return _pill('Video', Colors.teal);
    }
    if (pair.hasFront) return _pill('F only', Colors.orange);
    return _pill('B only', Colors.purple);
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.15),
      border:       Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  String _sortLabel(SortOrder s) => switch (s) {
    SortOrder.oldestFirst   => 'Date ↑',
    SortOrder.newestFirst   => 'Date ↓',
    SortOrder.nameAZ        => 'Name A-Z',
    SortOrder.nameZA        => 'Name Z-A',
    SortOrder.longestFirst  => 'Duration ↓',
    SortOrder.shortestFirst => 'Duration ↑',
  };

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

// ─── Export button with progress ─────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: enabled
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            if (isExporting)
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                  value:       progress,
                  strokeWidth: 1.5,
                  color:       const Color(0xFF4FC3F7),
                ),
              )
            else
              Icon(Icons.movie_creation_outlined,
                size: 14,
                color: enabled ? Colors.white60 : Colors.white24),
            const SizedBox(width: 5),
            Text(
              isExporting
                  ? '${((progress ?? 0) * 100).round()}%'
                  : 'Export',
              style: TextStyle(
                fontSize: 11,
                color: enabled ? Colors.white60 : Colors.white24,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Sync panel ───────────────────────────────────────────────────────────────

class _SyncPanel extends ConsumerWidget {
  final int syncOffsetMs;
  const _SyncPanel({required this.syncOffsetMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(color: Colors.white12, height: 10),
        Row(children: [
          const Text('Sync offset',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const Spacer(),
          Text(
            '${syncOffsetMs > 0 ? "+" : ""}$syncOffsetMs ms  '
            '(${syncOffsetMs > 0 ? "front ahead" : syncOffsetMs < 0 ? "back ahead" : "aligned"})',
            style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
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
            data: SliderTheme.of(context).copyWith(trackHeight: 2),
            child: Slider(
              min: -5000, max: 5000, divisions: 200,
              value:       syncOffsetMs.toDouble(),
              onChanged:   (v) =>
                  ref.read(syncOffsetProvider.notifier).state = v.round(),
              onChangeEnd: (v) =>
                  ref.read(playbackProvider.notifier).applySyncOffset(v.round()),
              activeColor:   const Color(0xFF4FC3F7),
              inactiveColor: Colors.white12,
            ),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          Text('-5 s',    style: TextStyle(color: Colors.white24, fontSize: 9)),
          Text('aligned', style: TextStyle(color: Colors.white24, fontSize: 9)),
          Text('+5 s',    style: TextStyle(color: Colors.white24, fontSize: 9)),
        ]),
      ]),
    );
  }
}

// ─── Tiny nav icon button ─────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;
  final String tooltip;
  const _NavBtn({
    required this.icon, required this.enabled,
    required this.onPressed, required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: ExcludeFocus(
      child: IconButton(
        icon: Icon(icon),
        color: enabled ? Colors.white70 : Colors.white24,
        onPressed: enabled ? onPressed : null,
        iconSize: 24,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    ),
  );
}

// ─── Volume button with slider popup ─────────────────────────────────────────

class _VolumeBtn extends StatefulWidget {
  final String label;
  final double volume; // 0-100
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
  bool _showSlider = false;

  bool get _muted => widget.volume <= 0;

  IconData get _icon {
    if (_muted) return Icons.volume_off_rounded;
    if (widget.volume < 50) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _showSlider = true),
      onExit: (_) => setState(() => _showSlider = false),
      child: SizedBox(
        // Reserve vertical space so the popup stays within the MouseRegion
        height: _showSlider ? 160 : 28,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomLeft,
          children: [
            // Mute/unmute icon button (anchored at bottom)
            Positioned(
              bottom: 0,
              left: 0,
              child: GestureDetector(
                onTap: widget.onMuteToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _muted
                        ? Colors.red.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _muted ? Colors.red.withValues(alpha: 0.5) : Colors.white12,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_icon, size: 13,
                        color: _muted ? Colors.redAccent : Colors.white54),
                    const SizedBox(width: 4),
                    Text(widget.label,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: _muted ? Colors.redAccent : Colors.white54)),
                  ]),
                ),
              ),
            ),
            // Vertical volume slider popup (appears above)
            if (_showSlider)
              Positioned(
                bottom: 32,
                left: 0,
                child: Container(
                  width: 36,
                  height: 120,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${widget.volume.round()}',
                        style: const TextStyle(color: Colors.white54,
                            fontSize: 9, fontWeight: FontWeight.w600)),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            activeTrackColor: _muted ? Colors.redAccent : const Color(0xFF4FC3F7),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: _muted ? Colors.redAccent : const Color(0xFF4FC3F7),
                            overlayColor: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
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
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Save button with spinner ────────────────────────────────────────────────

class _SaveBtn extends ConsumerWidget {
  final bool isSaving;
  final String? progressText;
  final VoidCallback? onPressed;
  const _SaveBtn({required this.isSaving, this.progressText, required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(shortcutConfigProvider);
    return Tooltip(
      message: isSaving ? 'Saving...' : 'Save clip files to a folder (${sc.label(ShortcutAction.saveClips)})',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSaving
                ? const Color(0xFF4FC3F7).withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSaving
                  ? const Color(0xFF4FC3F7).withValues(alpha: 0.4)
                  : Colors.white12,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isSaving)
              const SizedBox(
                width: 13, height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF4FC3F7),
                ),
              )
            else
              Icon(Icons.save_alt_rounded, size: 13,
                  color: onPressed != null ? Colors.white54 : Colors.white24),
            const SizedBox(width: 5),
            Text(
              isSaving ? (progressText ?? 'Saving...') : 'Save',
              style: TextStyle(
                fontSize: 11,
                color: isSaving
                    ? const Color(0xFF4FC3F7)
                    : onPressed != null ? Colors.white54 : Colors.white24,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Tool text+icon button ────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   tooltip;
  final VoidCallback onPressed;
  const _ToolBtn({
    super.key,
    required this.icon, required this.label,
    required this.tooltip, required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
    ),
  );
}

// ─── Speed control button ───────────────────────────────────────────────────

class _SpeedBtn extends ConsumerWidget {
  final bool enabled;
  final ValueChanged<double> onChanged;
  const _SpeedBtn({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    final sc    = ref.watch(shortcutConfigProvider);
    final isNormal = speed == 1.0;

    return PopupMenuButton<double>(
      onSelected: onChanged,
      enabled: enabled,
      tooltip: 'Playback speed (${sc.label(ShortcutAction.speedDown)} / ${sc.label(ShortcutAction.speedUp)})',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => [
        for (final s in playbackSpeeds)
          PopupMenuItem(
            value: s,
            height: 36,
            child: Row(children: [
              if (s == speed)
                const Icon(Icons.check_rounded, size: 14, color: Color(0xFF4FC3F7))
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Text(
                s == s.roundToDouble() ? '${s.round()}x' : '${s}x',
                style: TextStyle(
                  fontSize: 12,
                  color: s == speed ? const Color(0xFF4FC3F7) : Colors.white60,
                  fontWeight: s == speed ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isNormal
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFF4FC3F7).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isNormal
                ? Colors.white12
                : const Color(0xFF4FC3F7).withValues(alpha: 0.5),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.speed_rounded, size: 13,
            color: isNormal
                ? (enabled ? Colors.white54 : Colors.white24)
                : const Color(0xFF4FC3F7)),
          const SizedBox(width: 4),
          Text(
            speed == speed.roundToDouble() ? '${speed.round()}x' : '${speed}x',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isNormal
                  ? (enabled ? Colors.white54 : Colors.white24)
                  : const Color(0xFF4FC3F7),
            ),
          ),
        ]),
      ),
    );
  }
}