// lib/providers/app_providers.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../models/video_pair.dart';
import '../models/layout_config.dart';
import '../utils/file_pairer.dart';

// ─────────────────────────────────────────
// 1. Video pair list
// ─────────────────────────────────────────

class VideoPairListNotifier extends StateNotifier<List<VideoPair>> {
  VideoPairListNotifier() : super([]);

  Future<void> loadFromRoot(Directory root) async {
    final pairs = await FilePairer.pairFromRoot(root);
    state = pairs;
  }

  void clear() => state = [];
}

final videoPairListProvider =
    StateNotifierProvider<VideoPairListNotifier, List<VideoPair>>(
  (ref) => VideoPairListNotifier(),
);

// ─────────────────────────────────────────
// 2. Current pair index
// ─────────────────────────────────────────

final currentIndexProvider = StateProvider<int>((ref) => 0);

final currentPairProvider = Provider<VideoPair?>((ref) {
  final list  = ref.watch(videoPairListProvider);
  final index = ref.watch(currentIndexProvider);
  if (list.isEmpty) return null;
  return list[index.clamp(0, list.length - 1)];
});

// ─────────────────────────────────────────
// 3. Layout configuration
// ─────────────────────────────────────────

final layoutConfigProvider =
    StateProvider<LayoutConfig>((ref) => const LayoutConfig());

// ─────────────────────────────────────────
// 4. Sync offset (milliseconds)
// ─────────────────────────────────────────

final syncOffsetProvider = StateProvider<int>((ref) => 0);

// ─────────────────────────────────────────
// 5. Playback — two media_kit Players
// ─────────────────────────────────────────

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  PlaybackNotifier()
      : super(PlaybackState.initial()) {
    _frontPlayer = Player();
    _backPlayer  = Player();
  }

  late final Player _frontPlayer;
  late final Player _backPlayer;

  Player get frontPlayer => _frontPlayer;
  Player get backPlayer  => _backPlayer;

  Future<void> loadPair(VideoPair pair, int syncOffsetMs) async {
    await Future.wait([
      _frontPlayer.stop(),
      _backPlayer.stop(),
    ]);

    final offset = syncOffsetMs != 0 ? syncOffsetMs : pair.syncOffsetMs;

    if (pair.hasFront) {
      await _frontPlayer.open(
        Media(pair.frontFile!.path),
        play: false,
      );
    }
    if (pair.hasBack) {
      await _backPlayer.open(
        Media(pair.backFile!.path),
        play: false,
      );
    }

    // Apply sync offset
    if (offset > 0 && pair.hasBack) {
      await _backPlayer.seek(Duration(milliseconds: offset));
    } else if (offset < 0 && pair.hasFront) {
      await _frontPlayer.seek(Duration(milliseconds: -offset));
    }

    state = PlaybackState(
      isPlaying: false,
      isLoaded:  true,
      hasFront:  pair.hasFront,
      hasBack:   pair.hasBack,
    );
  }

  Future<void> play() async {
    await Future.wait([
      if (state.hasFront) _frontPlayer.play(),
      if (state.hasBack)  _backPlayer.play(),
    ]);
    state = state.copyWith(isPlaying: true);
  }

  Future<void> pause() async {
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
    await Future.wait([
      if (state.hasFront) _frontPlayer.seek(position),
      if (state.hasBack)  _backPlayer.seek(position),
    ]);
  }

  Future<void> applySyncOffset(int offsetMs) async {
    final wasPlaying = state.isPlaying;
    if (wasPlaying) await pause();

    final base = _frontPlayer.state.position;

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

  @override
  void dispose() {
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
// 6. Playback state
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

  factory PlaybackState.initial() => const PlaybackState(
        isPlaying: false,
        isLoaded:  false,
      );

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
// 7. Export progress
// ─────────────────────────────────────────

final exportProgressProvider = StateProvider<double?>((ref) => null);