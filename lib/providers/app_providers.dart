// lib/providers/app_providers.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../models/video_pair.dart';
import '../models/layout_config.dart';
import '../utils/file_pairer.dart';

// ─────────────────────────────────────────
// 1. Video pair list
// ─────────────────────────────────────────

class VideoPairListNotifier extends StateNotifier<List<VideoPair>> {
  VideoPairListNotifier() : super([]);

  Future<void> loadFromDirectory(Directory dir) async {
    final pairs = await FilePairer.pairFiles(dir);
    state = pairs;
  }

  Future<void> loadFromTwoDirectories(Directory frontDir, Directory backDir) async {
    final pairs = await FilePairer.pairFromTwoDirectories(frontDir, backDir);
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

final layoutConfigProvider = StateProvider<LayoutConfig>((ref) => const LayoutConfig());

// ─────────────────────────────────────────
// 4. Sync offset (milliseconds, front relative to back)
//    Positive → front is ahead; seek back forward to compensate
//    Negative → back is ahead; seek front forward to compensate
// ─────────────────────────────────────────

final syncOffsetProvider = StateProvider<int>((ref) => 0); // ms

// ─────────────────────────────────────────
// 5. Playback controller pair
// ─────────────────────────────────────────

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  PlaybackNotifier() : super(PlaybackState.initial());

  VideoPlayerController? _frontCtrl;
  VideoPlayerController? _backCtrl;

  Future<void> loadPair(VideoPair pair, int syncOffsetMs) async {
    await _disposeControllers();

    final front = VideoPlayerController.file(pair.frontFile);
    final back  = VideoPlayerController.file(pair.backFile);

    await Future.wait([front.initialize(), back.initialize()]);

    // Apply initial sync offset
    if (syncOffsetMs > 0) {
      await back.seekTo(Duration(milliseconds: syncOffsetMs));
    } else if (syncOffsetMs < 0) {
      await front.seekTo(Duration(milliseconds: -syncOffsetMs));
    }

    _frontCtrl = front;
    _backCtrl  = back;

    state = PlaybackState(
      frontController: front,
      backController:  back,
      isPlaying:       false,
      isLoaded:        true,
    );
  }

  Future<void> play() async {
    await Future.wait([
      _frontCtrl?.play() ?? Future.value(),
      _backCtrl?.play()  ?? Future.value(),
    ]);
    state = state.copyWith(isPlaying: true);
  }

  Future<void> pause() async {
    await Future.wait([
      _frontCtrl?.pause() ?? Future.value(),
      _backCtrl?.pause()  ?? Future.value(),
    ]);
    state = state.copyWith(isPlaying: false);
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekTo(Duration position) async {
    await Future.wait([
      _frontCtrl?.seekTo(position) ?? Future.value(),
      _backCtrl?.seekTo(position)  ?? Future.value(),
    ]);
  }

  /// Re-apply sync offset without reloading the pair.
  Future<void> applySyncOffset(int offsetMs) async {
    if (_frontCtrl == null || _backCtrl == null) return;

    final basePosition = _frontCtrl!.value.position;
    final wasPlaying   = state.isPlaying;

    if (wasPlaying) await pause();

    // Reset both to the current front position, then offset back
    await _frontCtrl!.seekTo(basePosition);

    if (offsetMs > 0) {
      final backSeek = basePosition + Duration(milliseconds: offsetMs);
      await _backCtrl!.seekTo(backSeek);
    } else if (offsetMs < 0) {
      final frontSeek = basePosition + Duration(milliseconds: -offsetMs);
      await _frontCtrl!.seekTo(frontSeek);
      await _backCtrl!.seekTo(basePosition);
    } else {
      await _backCtrl!.seekTo(basePosition);
    }

    if (wasPlaying) await play();
  }

  Future<void> _disposeControllers() async {
    final f = _frontCtrl;
    final b = _backCtrl;
    _frontCtrl = null;
    _backCtrl  = null;
    state = PlaybackState.initial();
    await Future.wait([
      f?.dispose() ?? Future.value(),
      b?.dispose() ?? Future.value(),
    ]);
  }

  @override
  void dispose() {
    _frontCtrl?.dispose();
    _backCtrl?.dispose();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) => PlaybackNotifier(),
);

// ─────────────────────────────────────────
// 6. Playback state value object
// ─────────────────────────────────────────

class PlaybackState {
  final VideoPlayerController? frontController;
  final VideoPlayerController? backController;
  final bool isPlaying;
  final bool isLoaded;

  const PlaybackState({
    this.frontController,
    this.backController,
    required this.isPlaying,
    required this.isLoaded,
  });

  factory PlaybackState.initial() => const PlaybackState(
        frontController: null,
        backController:  null,
        isPlaying:       false,
        isLoaded:        false,
      );

  PlaybackState copyWith({
    VideoPlayerController? frontController,
    VideoPlayerController? backController,
    bool? isPlaying,
    bool? isLoaded,
  }) =>
      PlaybackState(
        frontController: frontController ?? this.frontController,
        backController:  backController  ?? this.backController,
        isPlaying:       isPlaying       ?? this.isPlaying,
        isLoaded:        isLoaded        ?? this.isLoaded,
      );
}

// ─────────────────────────────────────────
// 7. Export progress  (0.0 → 1.0, null = idle)
// ─────────────────────────────────────────

final exportProgressProvider = StateProvider<double?>((ref) => null);