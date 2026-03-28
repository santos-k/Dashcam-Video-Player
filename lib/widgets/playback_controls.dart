// lib/widgets/playback_controls.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_providers.dart';
import '../models/layout_config.dart';
import '../models/video_pair.dart';
import '../services/export_service.dart';

class PlaybackControls extends ConsumerStatefulWidget {
  final VoidCallback  onPrevious;
  final VoidCallback  onNext;
  final VoidCallback  onFolder;
  final VoidCallback  onLayout;
  final VoidCallback? onSaveClip;
  final VoidCallback? onCloseFolder;
  final VoidCallback? onMap;
  final VoidCallback? focusRequester;

  const PlaybackControls({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onFolder,
    required this.onLayout,
    this.onSaveClip,
    this.onCloseFolder,
    this.onMap,
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
    final frontMuted  = ref.watch(frontMutedProvider);
    final backMuted   = ref.watch(backMutedProvider);
    final isSaving    = ref.watch(savingClipsProvider);
    final notifier    = ref.read(playbackProvider.notifier);

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

          // Sort toggle
          _ToolBtn(
            icon: sortOrder == SortOrder.oldestFirst
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            label: sortOrder == SortOrder.oldestFirst
                ? 'Oldest first'
                : 'Newest first',
            tooltip: 'Toggle sort order (S)',
            onPressed: () {
              final next = sortOrder == SortOrder.oldestFirst
                  ? SortOrder.newestFirst
                  : SortOrder.oldestFirst;
              ref.read(sortOrderProvider.notifier).state = next;
              ref.read(videoPairListProvider.notifier).applySort(next);
              ref.read(currentIndexProvider.notifier).state = 0;
              widget.focusRequester?.call();
            },
          ),
          const SizedBox(width: 4),

          // Mute buttons — single button when only one camera, F/B when paired
          if (playback.hasFront && playback.hasBack) ...[
            _MuteBtn(
              label:   'F',
              tooltip: frontMuted ? 'Unmute front camera (F)' : 'Mute front camera (F)',
              muted:   frontMuted,
              onTap: () {
                final next = !frontMuted;
                ref.read(frontMutedProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setFrontMuted(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 4),
            _MuteBtn(
              label:   'B',
              tooltip: backMuted ? 'Unmute back camera (B)' : 'Mute back camera (B)',
              muted:   backMuted,
              onTap: () {
                final next = !backMuted;
                ref.read(backMutedProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setBackMuted(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 4),
          ] else if (playback.hasFront) ...[
            _MuteBtn(
              label:   'Mute',
              tooltip: frontMuted ? 'Unmute (M)' : 'Mute (M)',
              muted:   frontMuted,
              onTap: () {
                final next = !frontMuted;
                ref.read(frontMutedProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setFrontMuted(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 4),
          ] else if (playback.hasBack) ...[
            _MuteBtn(
              label:   'Mute',
              tooltip: backMuted ? 'Unmute (M)' : 'Mute (M)',
              muted:   backMuted,
              onTap: () {
                final next = !backMuted;
                ref.read(backMutedProvider.notifier).state = next;
                ref.read(playbackProvider.notifier).setBackMuted(next);
                widget.focusRequester?.call();
              },
            ),
            const SizedBox(width: 4),
          ],

          // Layout — only useful when both cameras are present
          if (playback.hasFront && playback.hasBack)
            _ToolBtn(
              icon:    Icons.view_quilt_rounded,
              label:   _layoutLabel(layout.mode),
              tooltip: 'Change layout (L)',
              onPressed: widget.onLayout,
            ),
          const SizedBox(width: 4),

          // Open folder
          _ToolBtn(
            icon:    Icons.folder_open_rounded,
            label:   'Open',
            tooltip: 'Open dashcam folder (O)',
            onPressed: widget.onFolder,
          ),
          const SizedBox(width: 4),

          // Map
          _ToolBtn(
            icon:    Icons.map_rounded,
            label:   'Map',
            tooltip: 'Show GPS location on map (M)',
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
            onPressed: isSaving ? null : () {
              widget.onSaveClip?.call();
            },
          ),
          const SizedBox(width: 4),

          // Close folder
          _ToolBtn(
            icon:    Icons.close_rounded,
            label:   'Close',
            tooltip: 'Close loaded folder (W)',
            onPressed: () {
              widget.onCloseFolder?.call();
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
            enabled: hasPrev, tooltip: 'Previous (Shift+,)',
            onPressed: () { widget.onPrevious(); widget.focusRequester?.call(); }),
          _NavBtn(icon: Icons.replay_10_rounded,
            enabled: isLoaded, tooltip: 'Back 10s (←)',
            onPressed: () {
              notifier.seekRelative(const Duration(seconds: -10));
              widget.focusRequester?.call();
            }),

          const SizedBox(width: 8),
          // Play/Pause big button
          Tooltip(
            message: 'Play / Pause (Space)',
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
            enabled: isLoaded, tooltip: 'Forward 10s (→)',
            onPressed: () {
              notifier.seekRelative(const Duration(seconds: 10));
              widget.focusRequester?.call();
            }),
          _NavBtn(icon: Icons.skip_next_rounded,
            enabled: hasNext, tooltip: 'Next (Shift+.)',
            onPressed: () { widget.onNext(); widget.focusRequester?.call(); }),

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

    ref.read(exportProgressProvider.notifier).state = 0.0;

    final ok = await ExportService.exportPair(
      pair:         pair,
      layout:       layout,
      syncOffsetMs: syncOffset,
      outputPath:   savePath,
      onProgress:   (p) =>
          ref.read(exportProgressProvider.notifier).state = p,
    );

    ref.read(exportProgressProvider.notifier).state = null;

    if (mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Exported to $savePath'
            : 'Export failed — is FFmpeg installed?'),
        duration: const Duration(seconds: 4),
        action: ok
            ? SnackBarAction(
                label: 'Open folder',
                onPressed: () => Process.run(
                    'explorer', ['/select,', savePath]),
              )
            : null,
      ));
    }
  }

  Widget _statusBadge(VideoPair pair) {
    if (pair.isPaired)  return _pill('F+B',    const Color(0xFF4FC3F7));
    if (pair.hasFront)  return _pill('F only', Colors.orange);
    return                     _pill('B only', Colors.purple);
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

  String _layoutLabel(LayoutMode m) => switch (m) {
    LayoutMode.sideBySide => 'Side-by-side',
    LayoutMode.stacked    => 'Stacked',
    LayoutMode.pip        => 'PIP',
  };

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Export button with progress ─────────────────────────────────────────────

class _ExportBtn extends StatelessWidget {
  final bool    enabled;
  final double? progress;
  final VoidCallback onExport;

  const _ExportBtn({
    required this.enabled,
    required this.progress,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final isExporting = progress != null;

    return Tooltip(
      message: 'Export current clip (FFmpeg required)',
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

// ─── Mute button ─────────────────────────────────────────────────────────────

class _MuteBtn extends StatelessWidget {
  final String   label;
  final String   tooltip;
  final bool     muted;
  final VoidCallback onTap;
  const _MuteBtn({required this.label, required this.tooltip, required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: muted
                ? Colors.red.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: muted ? Colors.red.withValues(alpha: 0.5) : Colors.white12,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 13,
              color: muted ? Colors.redAccent : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted ? Colors.redAccent : Colors.white54,
              )),
          ]),
        ),
      ),
    );
  }
}

// ─── Save button with spinner ────────────────────────────────────────────────

class _SaveBtn extends StatelessWidget {
  final bool isSaving;
  final VoidCallback? onPressed;
  const _SaveBtn({required this.isSaving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isSaving ? 'Saving...' : 'Save clip files to a folder',
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
              isSaving ? 'Saving...' : 'Save',
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