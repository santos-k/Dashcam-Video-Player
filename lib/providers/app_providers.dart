// lib/providers/app_providers.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../models/video_pair.dart';
import '../models/layout_config.dart';
import '../utils/file_pairer.dart';
import '../services/log_service.dart';

// ─────────────────────────────────────────
// 1. Sort order
// ─────────────────────────────────────────

enum SortOrder { newestFirst, oldestFirst }

final sortOrderProvider = StateProvider<SortOrder>((ref) => SortOrder.oldestFirst);

// ─────────────────────────────────────────
// 2. Video pair list
// ─────────────────────────────────────────

class VideoPairListNotifier extends StateNotifier<List<VideoPair>> {
  VideoPairListNotifier() : super([]);

  List<VideoPair> _raw = [];

  Future<void> loadFromRoot(Directory root) async {
    final pairs = await FilePairer.pairFromRoot(root);
    appLog('Folder', 'Loaded ${pairs.length} pairs from ${root.path}');
    _raw  = pairs; // oldest first from pairer
    state = pairs;
  }

  void applySort(SortOrder order) {
    if (_raw.isEmpty) return;
    state = order == SortOrder.newestFirst
        ? _raw.reversed.toList()
        : List.of(_raw);
  }

  void clear() {
    _raw  = [];
    state = [];
  }
}

final videoPairListProvider =
    StateNotifierProvider<VideoPairListNotifier, List<VideoPair>>(
  (ref) {
    final notifier = VideoPairListNotifier();
    // Re-sort whenever sort order changes
    ref.listen(sortOrderProvider, (_, order) => notifier.applySort(order));
    return notifier;
  },
);

// ─────────────────────────────────────────
// 3. Current pair index
// ─────────────────────────────────────────

final currentIndexProvider = StateProvider<int>((ref) => 0);

final currentPairProvider = Provider<VideoPair?>((ref) {
  final list  = ref.watch(videoPairListProvider);
  final index = ref.watch(currentIndexProvider);
  if (list.isEmpty) return null;
  return list[index.clamp(0, list.length - 1)];
});

// ─────────────────────────────────────────
// 4. Layout configuration
// ─────────────────────────────────────────

final layoutConfigProvider =
    StateProvider<LayoutConfig>((ref) => const LayoutConfig());

// ─────────────────────────────────────────
// 5. Sync offset (milliseconds)
// ─────────────────────────────────────────

final syncOffsetProvider = StateProvider<int>((ref) => 0);

// ─────────────────────────────────────────
// 6. Playback notifier
// ─────────────────────────────────────────

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  PlaybackNotifier() : super(PlaybackState.initial()) {
    _frontPlayer = Player();
    _backPlayer  = Player();
  }

  late final Player _frontPlayer;
  late final Player _backPlayer;
  StreamSubscription<bool>? _endSub;

  Player get frontPlayer => _frontPlayer;
  Player get backPlayer  => _backPlayer;

  /// Called by the UI when a clip ends — advances to next pair.
  VoidCallback? onClipEnd;

  Future<void> loadPair(VideoPair pair, int syncOffsetMs,
      {bool autoPlay = false}) async {
    appLog('Playback', 'loadPair: ${pair.id} (front=${pair.hasFront}, back=${pair.hasBack}, offset=$syncOffsetMs, autoPlay=$autoPlay)');
    // Stop both first
    _frontPlayer.pause();
    _backPlayer.pause();

    state = PlaybackState(
      isPlaying: false,
      isLoaded:  false,
      hasFront:  pair.hasFront,
      hasBack:   pair.hasBack,
    );

    final offset = syncOffsetMs != 0 ? syncOffsetMs : pair.syncOffsetMs;

    try {
      await Future.wait([
        if (pair.hasFront)
          _frontPlayer.open(Media(pair.frontFile!.path), play: false),
        if (pair.hasBack)
          _backPlayer.open(Media(pair.backFile!.path),   play: false),
      ]);
    } catch (e) {
      debugPrint('media_kit open error: $e');
    }

    // Apply sync offset
    if (offset > 0 && pair.hasBack) {
      await _backPlayer.seek(Duration(milliseconds: offset));
    } else if (offset < 0 && pair.hasFront) {
      await _frontPlayer.seek(Duration(milliseconds: -offset));
    }

    state = PlaybackState(
      isPlaying: autoPlay,
      isLoaded:  true,
      hasFront:  pair.hasFront,
      hasBack:   pair.hasBack,
    );

    if (autoPlay) {
      await Future.wait([
        if (pair.hasFront) _frontPlayer.play(),
        if (pair.hasBack)  _backPlayer.play(),
      ]);
    }

    // Listen for end-of-file on the primary player
    _listenForEnd(pair);
  }

  void _listenForEnd(VideoPair pair) {
    _endSub?.cancel();
    // Use front player if available, otherwise back
    final primary = pair.hasFront ? _frontPlayer : _backPlayer;
    _endSub = primary.stream.completed.listen((completed) {
      if (completed && onClipEnd != null) {
        onClipEnd!();
      }
    });
  }

  Future<void> play() async {
    // If the clip has finished, seek to start before playing so we
    // don't instantly trigger "completed" again.
    final primary = state.hasFront ? _frontPlayer : _backPlayer;
    final pos = primary.state.position;
    final dur = primary.state.duration;
    if (dur > Duration.zero &&
        pos >= dur - const Duration(milliseconds: 300)) {
      appLog('Playback', 'Play (restarting from beginning)');
      await seekTo(Duration.zero);
    } else {
      appLog('Playback', 'Play');
    }
    await Future.wait([
      if (state.hasFront) _frontPlayer.play(),
      if (state.hasBack)  _backPlayer.play(),
    ]);
    state = state.copyWith(isPlaying: true);
  }

  Future<void> pause() async {
    appLog('Playback', 'Pause');
    await Future.wait([
      _frontPlayer.pause(),
      _backPlayer.pause(),
    ]);
    state = state.copyWith(isPlaying: false);
  }

  Future<void> togglePlay() async {
    state.isPlaying ? await pause() : await play();
  }

  Future<void> seekTo(Duration position) async {
    final d = position < Duration.zero ? Duration.zero : position;
    await Future.wait([
      if (state.hasFront) _frontPlayer.seek(d),
      if (state.hasBack)  _backPlayer.seek(d),
    ]);
  }

  Future<void> seekRelative(Duration delta) async {
    final base = (state.hasFront
            ? _frontPlayer.state.position
            : _backPlayer.state.position) +
        delta;
    await seekTo(base);
  }

  Future<void> applySyncOffset(int offsetMs) async {
    final wasPlaying = state.isPlaying;
    if (wasPlaying) await pause();

    final base = state.hasFront
        ? _frontPlayer.state.position
        : _backPlayer.state.position;

    if (offsetMs > 0 && state.hasBack) {
      await _frontPlayer.seek(base);
      await _backPlayer.seek(base + Duration(milliseconds: offsetMs));
    } else if (offsetMs < 0 && state.hasFront) {
      await _frontPlayer.seek(base + Duration(milliseconds: -offsetMs));
      await _backPlayer.seek(base);
    } else {
      await _frontPlayer.seek(base);
      await _backPlayer.seek(base);
    }

    if (wasPlaying) await play();
  }

  Future<void> stop() async {
    appLog('Playback', 'Stop (reset to initial)');
    _endSub?.cancel();
    _endSub = null;
    await Future.wait([
      _frontPlayer.stop(),
      _backPlayer.stop(),
    ]);
    state = PlaybackState.initial();
  }

  Future<void> setFrontMuted(bool muted) async {
    await _frontPlayer.setVolume(muted ? 0 : 100);
  }

  Future<void> setBackMuted(bool muted) async {
    await _backPlayer.setVolume(muted ? 0 : 100);
  }

  @override
  void dispose() {
    _endSub?.cancel();
    _frontPlayer.dispose();
    _backPlayer.dispose();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) => PlaybackNotifier(),
);

// ─────────────────────────────────────────
// 7. Playback state
// ─────────────────────────────────────────

class PlaybackState {
  final bool isPlaying;
  final bool isLoaded;
  final bool hasFront;
  final bool hasBack;

  const PlaybackState({
    required this.isPlaying,
    required this.isLoaded,
    this.hasFront = false,
    this.hasBack  = false,
  });

  factory PlaybackState.initial() =>
      const PlaybackState(isPlaying: false, isLoaded: false);

  PlaybackState copyWith({
    bool? isPlaying,
    bool? isLoaded,
    bool? hasFront,
    bool? hasBack,
  }) =>
      PlaybackState(
        isPlaying: isPlaying ?? this.isPlaying,
        isLoaded:  isLoaded  ?? this.isLoaded,
        hasFront:  hasFront  ?? this.hasFront,
        hasBack:   hasBack   ?? this.hasBack,
      );
}

// ─────────────────────────────────────────
// 8. Export progress (single clip)
// ─────────────────────────────────────────

final exportProgressProvider = StateProvider<double?>((ref) => null);

// ─────────────────────────────────────────
// 9b. Batch export progress  (current, total)
// ─────────────────────────────────────────

class BatchExportState {
  final int     current;
  final int     total;
  final double  clipProgress; // 0-1 within current clip
  const BatchExportState(this.current, this.total, this.clipProgress);
  double get overallProgress =>
      (current + clipProgress) / total;
}

final batchExportProvider = StateProvider<BatchExportState?>((ref) => null);


// ─────────────────────────────────────────
// 10. Save-in-progress flag
// ─────────────────────────────────────────

final savingClipsProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────
// 9. Mute state per camera
// ─────────────────────────────────────────

final frontMutedProvider = StateProvider<bool>((ref) => false);
final backMutedProvider  = StateProvider<bool>((ref) => false);

// PIP position reset signal
final pipResetProvider = StateProvider<int>((ref) => 0);