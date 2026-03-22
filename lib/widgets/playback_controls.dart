// lib/widgets/playback_controls.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final playback    = ref.watch(playbackProvider);
    final pairs       = ref.watch(videoPairListProvider);
    final index       = ref.watch(currentIndexProvider);
    final syncOffset  = ref.watch(syncOffsetProvider);
    final notifier    = ref.read(playbackProvider.notifier);

    final hasPrev  = index > 0;
    final hasNext  = index < pairs.length - 1;
    final isLoaded = playback.isLoaded;

    // Listen to position for the seek bar
    final duration = playback.frontController?.value.duration ?? Duration.zero;
    final position = playback.frontController?.value.position ?? Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Seek bar ────────────────────────────────────
          Row(
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              Expanded(
                child: Slider(
                  value:   progress.clamp(0.0, 1.0),
                  onChanged: isLoaded
                      ? (v) => notifier.seekTo(
                            Duration(
                              milliseconds:
                                  (v * duration.inMilliseconds).round(),
                            ),
                          )
                      : null,
                  activeColor:   const Color(0xFF4FC3F7),
                  inactiveColor: Colors.white12,
                  thumbColor:    Colors.white,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),

          // ── Transport controls ───────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous pair
              _ControlButton(
                icon:      Icons.skip_previous_rounded,
                enabled:   hasPrev,
                onPressed: () => _goTo(context, ref, index - 1),
                tooltip:   'Previous clip',
              ),
              const SizedBox(width: 8),

              // Rewind 10 s
              _ControlButton(
                icon:    Icons.replay_10_rounded,
                enabled: isLoaded,
                onPressed: () => notifier.seekTo(
                  position - const Duration(seconds: 10),
                ),
                tooltip: 'Back 10 s',
              ),
              const SizedBox(width: 8),

              // Play / Pause
              GestureDetector(
                onTap: isLoaded ? notifier.togglePlay : null,
                child: Container(
                  width:  52,
                  height: 52,
                  decoration: BoxDecoration(
                    color:       isLoaded
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

              // Forward 10 s
              _ControlButton(
                icon:    Icons.forward_10_rounded,
                enabled: isLoaded,
                onPressed: () => notifier.seekTo(
                  position + const Duration(seconds: 10),
                ),
                tooltip: 'Forward 10 s',
              ),
              const SizedBox(width: 8),

              // Next pair
              _ControlButton(
                icon:      Icons.skip_next_rounded,
                enabled:   hasNext,
                onPressed: () => _goTo(context, ref, index + 1),
                tooltip:   'Next clip',
              ),

              const Spacer(),

              // Sync toggle
              Tooltip(
                message: 'Manual sync',
                child: TextButton.icon(
                  onPressed: () => setState(() => _showSync = !_showSync),
                  icon: Icon(
                    Icons.sync_rounded,
                    color: _showSync
                        ? const Color(0xFF4FC3F7)
                        : Colors.white54,
                    size: 18,
                  ),
                  label: Text(
                    syncOffset == 0
                        ? 'Sync'
                        : (syncOffset > 0 ? '+${syncOffset}ms' : '${syncOffset}ms'),
                    style: TextStyle(
                      color: _showSync
                          ? const Color(0xFF4FC3F7)
                          : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Sync slider (collapsed by default) ──────────
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

  void _goTo(BuildContext ctx, WidgetRef ref, int targetIndex) {
    final pairs = ref.read(videoPairListProvider);
    if (targetIndex < 0 || targetIndex >= pairs.length) return;

    ref.read(currentIndexProvider.notifier).state = targetIndex;
    ref.read(syncOffsetProvider.notifier).state   = 0; // reset sync

    final pair      = pairs[targetIndex];
    final notifier  = ref.read(playbackProvider.notifier);
    notifier.loadPair(pair, 0);
  }

  String _formatDuration(Duration d) {
    final h  = d.inHours;
    final m  = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s  = d.inSeconds.remainder(60).toString().padLeft(2, '0');
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
          Divider(color: Colors.white12, height: 12),
          Row(
            children: [
              const Text(
                'Sync offset',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '${syncOffsetMs > 0 ? "+" : ""}$syncOffsetMs ms  '
                '(${syncOffsetMs > 0 ? "front ahead" : syncOffsetMs < 0 ? "back ahead" : "aligned"})',
                style: const TextStyle(
                  color: Color(0xFF4FC3F7),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  ref.read(syncOffsetProvider.notifier).state = 0;
                  ref.read(playbackProvider.notifier).applySyncOffset(0);
                },
                child: const Text(
                  'Reset',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
          Slider(
            min:           -5000,
            max:            5000,
            divisions:      200,
            value:          syncOffsetMs.toDouble(),
            onChanged: (v) {
              ref.read(syncOffsetProvider.notifier).state = v.round();
            },
            onChangeEnd: (v) {
              ref.read(playbackProvider.notifier).applySyncOffset(v.round());
            },
            activeColor:   const Color(0xFF4FC3F7),
            inactiveColor: Colors.white12,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('-5 s', style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text('aligned', style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text('+5 s', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Helper button ────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;
  final String tooltip;

  const _ControlButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon:  Icon(icon),
        color: enabled ? Colors.white70 : Colors.white24,
        onPressed: enabled ? onPressed : null,
        iconSize: 26,
      ),
    );
  }
}