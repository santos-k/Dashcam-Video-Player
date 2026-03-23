// lib/widgets/playback_controls.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../providers/app_providers.dart';

class PlaybackControls extends ConsumerStatefulWidget {
  const PlaybackControls({super.key});

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls> {
  bool _showSync = false;

  @override
  Widget build(BuildContext context) {
    final playback   = ref.watch(playbackProvider);
    final pairs      = ref.watch(videoPairListProvider);
    final index      = ref.watch(currentIndexProvider);
    final syncOffset = ref.watch(syncOffsetProvider);
    final notifier   = ref.read(playbackProvider.notifier);

    final hasPrev  = index > 0;
    final hasNext  = index < pairs.length - 1;
    final isLoaded = playback.isLoaded;

    // Use front player for position/duration; fall back to back
    final player = playback.hasFront
        ? notifier.frontPlayer
        : notifier.backPlayer;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Seek bar ──────────────────────────────────
          StreamBuilder<Duration>(
            stream: player.stream.position,
            builder: (context, posSnap) {
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                builder: (context, durSnap) {
                  final position = posSnap.data ?? Duration.zero;
                  final duration = durSnap.data ?? Duration.zero;
                  final progress = duration.inMilliseconds > 0
                      ? position.inMilliseconds / duration.inMilliseconds
                      : 0.0;

                  return Row(children: [
                    Text(_fmt(position),
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value:     progress.clamp(0.0, 1.0),
                        onChanged: isLoaded
                            ? (v) => notifier.seekTo(Duration(
                                milliseconds: (v * duration.inMilliseconds).round()))
                            : null,
                        activeColor:   const Color(0xFF4FC3F7),
                        inactiveColor: Colors.white12,
                        thumbColor:    Colors.white,
                      ),
                    ),
                    Text(_fmt(duration),
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ]);
                },
              );
            },
          ),

          // ── Transport controls ────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Btn(icon: Icons.skip_previous_rounded, enabled: hasPrev,
                  tooltip: 'Previous clip',
                  onPressed: () => _goTo(ref, index - 1)),
              const SizedBox(width: 8),
              _Btn(icon: Icons.replay_10_rounded, enabled: isLoaded,
                  tooltip: 'Back 10s',
                  onPressed: () async {
                    final pos = player.state.position;
                    await notifier.seekTo(pos - const Duration(seconds: 10));
                  }),
              const SizedBox(width: 8),

              // Play/Pause
              GestureDetector(
                onTap: isLoaded ? notifier.togglePlay : null,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: isLoaded
                        ? const Color(0xFF4FC3F7)
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Icon(
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: isLoaded ? Colors.black : Colors.white24,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              _Btn(icon: Icons.forward_10_rounded, enabled: isLoaded,
                  tooltip: 'Forward 10s',
                  onPressed: () async {
                    final pos = player.state.position;
                    await notifier.seekTo(pos + const Duration(seconds: 10));
                  }),
              const SizedBox(width: 8),
              _Btn(icon: Icons.skip_next_rounded, enabled: hasNext,
                  tooltip: 'Next clip',
                  onPressed: () => _goTo(ref, index + 1)),

              const Spacer(),

              // Sync button
              TextButton.icon(
                onPressed: () => setState(() => _showSync = !_showSync),
                icon: Icon(Icons.sync_rounded,
                    color: _showSync
                        ? const Color(0xFF4FC3F7)
                        : Colors.white54,
                    size: 18),
                label: Text(
                  syncOffset == 0
                      ? 'Sync'
                      : '${syncOffset > 0 ? "+" : ""}${syncOffset}ms',
                  style: TextStyle(
                    color: _showSync
                        ? const Color(0xFF4FC3F7)
                        : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          // ── Sync slider ───────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showSync
                ? _SyncSlider(syncOffsetMs: syncOffset)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _goTo(WidgetRef ref, int targetIndex) {
    final pairs = ref.read(videoPairListProvider);
    if (targetIndex < 0 || targetIndex >= pairs.length) return;
    ref.read(currentIndexProvider.notifier).state = targetIndex;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    ref.read(playbackProvider.notifier).loadPair(pairs[targetIndex], 0);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Sync Slider ─────────────────────────────────────────────────────────────

class _SyncSlider extends ConsumerWidget {
  final int syncOffsetMs;
  const _SyncSlider({required this.syncOffsetMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white12, height: 12),
          Row(children: [
            const Text('Sync offset',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text(
              '${syncOffsetMs > 0 ? "+" : ""}$syncOffsetMs ms  '
              '(${syncOffsetMs > 0 ? "front ahead" : syncOffsetMs < 0 ? "back ahead" : "aligned"})',
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                ref.read(syncOffsetProvider.notifier).state = 0;
                ref.read(playbackProvider.notifier).applySyncOffset(0);
              },
              child: const Text('Reset',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ]),
          Slider(
            min: -5000, max: 5000, divisions: 200,
            value:        syncOffsetMs.toDouble(),
            onChanged:    (v) =>
                ref.read(syncOffsetProvider.notifier).state = v.round(),
            onChangeEnd:  (v) =>
                ref.read(playbackProvider.notifier).applySyncOffset(v.round()),
            activeColor:   const Color(0xFF4FC3F7),
            inactiveColor: Colors.white12,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('-5 s',    style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text('aligned', style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text('+5 s',    style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Helper button ────────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;
  final String tooltip;
  const _Btn({
    required this.icon, required this.enabled,
    required this.onPressed, required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      icon:      Icon(icon),
      color:     enabled ? Colors.white70 : Colors.white24,
      onPressed: enabled ? onPressed : null,
      iconSize:  26,
    ),
  );
}