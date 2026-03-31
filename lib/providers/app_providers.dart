// lib/providers/app_providers.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../models/dashcam_file.dart';
import '../models/video_pair.dart';
import '../models/layout_config.dart';
import '../models/shortcut_action.dart';
import '../utils/file_pairer.dart';
import '../services/log_service.dart';
import '../services/shortcut_service.dart';

// ─────────────────────────────────────────
// 1. Sort order
// ─────────────────────────────────────────

enum SortOrder { newestFirst, oldestFirst, nameAZ, nameZA, longestFirst, shortestFirst }

final sortOrderProvider = StateProvider<SortOrder>((ref) => SortOrder.oldestFirst);

// ─────────────────────────────────────────
// 1b. Clip view mode & selection
// ─────────────────────────────────────────

enum ClipViewMode { text, thumbnail }

final clipViewModeProvider = StateProvider<ClipViewMode>((ref) => ClipViewMode.text);

/// Whether the clip list is in multi-select mode.
final clipSelectionModeProvider = StateProvider<bool>((ref) => false);

/// Indices of selected clips (used for save/delete actions in the drawer).
final selectedClipIndicesProvider = StateProvider<Set<int>>((ref) => {});

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

  /// Duration cache reference for duration-based sorting.
  Map<String, Duration> _durationCache = {};

  void setDurationCache(Map<String, Duration> cache) {
    _durationCache = cache;
  }

  void applySort(SortOrder order) {
    if (_raw.isEmpty) return;
    final sorted = List.of(_raw);
    switch (order) {
      case SortOrder.oldestFirst:
        sorted.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      case SortOrder.newestFirst:
        sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      case SortOrder.nameAZ:
        sorted.sort((a, b) => a.id.compareTo(b.id));
      case SortOrder.nameZA:
        sorted.sort((a, b) => b.id.compareTo(a.id));
      case SortOrder.longestFirst:
        sorted.sort((a, b) {
          final da = _durationCache[a.id]?.inSeconds ?? 0;
          final db = _durationCache[b.id]?.inSeconds ?? 0;
          return db.compareTo(da);
        });
      case SortOrder.shortestFirst:
        sorted.sort((a, b) {
          final da = _durationCache[a.id]?.inSeconds ?? 0;
          final db = _durationCache[b.id]?.inSeconds ?? 0;
          return da.compareTo(db);
        });
    }
    state = sorted;
  }

  /// Remove pairs at the given indices (referencing current [state] order)
  /// and return the removed pairs.
  List<VideoPair> removePairs(Set<int> indices) {
    // Collect the actual VideoPair objects to remove (by identity, not index)
    final toRemove = <VideoPair>{};
    for (final i in indices) {
      if (i >= 0 && i < state.length) {
        toRemove.add(state[i]);
      }
    }
    _raw.removeWhere((p) => toRemove.contains(p));
    state = List.of(_raw);
    return toRemove.toList();
  }

  /// Load dashcam WiFi files and pair them into VideoPairs.
  /// Merges with any existing local pairs.
  void loadFromDashcam(List<DashcamFile> files) {
    final wifiPairs = FilePairer.pairFromDashcam(files);
    appLog('Dashcam', 'Paired ${wifiPairs.length} clips from WiFi dashcam');

    // Remove any previous WiFi pairs, keep local ones
    _raw.removeWhere((p) => p.isRemote);
    _raw.addAll(wifiPairs);
    _raw.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = List.of(_raw);
  }

  /// Remove all WiFi dashcam pairs (on disconnect).
  void clearDashcamPairs() {
    _raw.removeWhere((p) => p.isRemote);
    state = List.of(_raw);
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

  /// Called when a clip duration is resolved after loading.
  void Function(String clipId, Duration duration)? onDurationResolved;

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
          _frontPlayer.open(Media(pair.frontPath!), play: false),
        if (pair.hasBack)
          _backPlayer.open(Media(pair.backPath!),   play: false),
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

    // Cache the clip duration
    Future.delayed(const Duration(milliseconds: 500), () {
      final primary = pair.hasFront ? _frontPlayer : _backPlayer;
      final dur = primary.state.duration;
      if (dur > Duration.zero) {
        onDurationResolved?.call(pair.id, dur);
      }
    });

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

  Future<void> setFrontVolume(double volume) async {
    await _frontPlayer.setVolume(volume.clamp(0, 100));
  }

  Future<void> setBackVolume(double volume) async {
    await _backPlayer.setVolume(volume.clamp(0, 100));
  }

  Future<void> setSpeed(double speed) async {
    appLog('Playback', 'Set speed: ${speed}x');
    await Future.wait([
      _frontPlayer.setRate(speed),
      _backPlayer.setRate(speed),
    ]);
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

/// null = not saving, non-null = progress text (e.g. "1/4 saved")
final savingClipsProvider = StateProvider<String?>((ref) => null);

// ─────────────────────────────────────────
// 9. Clip duration cache (populated after each loadPair)
// ─────────────────────────────────────────

final clipDurationCacheProvider = StateProvider<Map<String, Duration>>((ref) => {});

// ─────────────────────────────────────────
// 10. Volume per camera (0.0 - 100.0)
// ─────────────────────────────────────────

final frontVolumeProvider = StateProvider<double>((ref) => 100.0);
final backVolumeProvider  = StateProvider<double>((ref) => 100.0);

// PIP position reset signal
final pipResetProvider = StateProvider<int>((ref) => 0);

// PIP export position — fractions (0..1) of available drag range.
// (-1, -1) = use default alignment-based position.
final pipExportPositionProvider = StateProvider<(double, double)>((ref) => (-1.0, -1.0));

// ─────────────────────────────────────────
// 11. Persisted map state (survives sidebar open/close)
// ─────────────────────────────────────────

class MapState {
  final double? lat;
  final double? lon;
  final double  zoom;
  final int     tileLayer;
  const MapState({this.lat, this.lon, this.zoom = 5, this.tileLayer = 0});
  MapState copyWith({double? lat, double? lon, double? zoom, int? tileLayer}) =>
      MapState(
        lat:       lat       ?? this.lat,
        lon:       lon       ?? this.lon,
        zoom:      zoom      ?? this.zoom,
        tileLayer: tileLayer ?? this.tileLayer,
      );
}

final mapStateProvider = StateProvider<MapState>((ref) => const MapState());

// ─────────────────────────────────────────
// 12. Playback speed
// ─────────────────────────────────────────

const playbackSpeeds = [0.1, 0.2, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0];

final playbackSpeedProvider = StateProvider<double>((ref) => 1.0);

// ─────────────────────────────────────────
// 13. Keyboard shortcut configuration
// ─────────────────────────────────────────

class ShortcutConfigNotifier extends StateNotifier<ShortcutConfig> {
  ShortcutConfigNotifier() : super(ShortcutService.load());

  void updateBinding(ShortcutAction action, KeyBinding binding) {
    state = state.withBinding(action, binding);
    ShortcutService.save(state);
  }

  void resetToDefaults() {
    state = ShortcutConfig.defaults();
    ShortcutService.save(state);
  }
}

final shortcutConfigProvider =
    StateNotifierProvider<ShortcutConfigNotifier, ShortcutConfig>(
  (ref) => ShortcutConfigNotifier(),
);

