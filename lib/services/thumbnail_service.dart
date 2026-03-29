// lib/services/thumbnail_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Generates and caches video thumbnails via FFmpeg.
class ThumbnailService {
  ThumbnailService._();

  static String? _cacheDir;
  static String? _ffmpegPath;
  static bool    _ffmpegChecked = false;
  static final Map<String, String> _memCache = {};

  // Limit concurrent FFmpeg processes to avoid overwhelming the system
  static int _activeJobs = 0;
  static const int _maxConcurrent = 4;
  static final List<Completer<void>> _jobQueue = [];

  /// Returns the cache directory, creating it if needed.
  static Future<String> _ensureCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tmp = Directory.systemTemp.path;
    final dir = Directory(p.join(tmp, 'dashcam_player_thumbs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir.path;
    return _cacheDir!;
  }

  static Future<String?> _getFFmpeg() async {
    if (_ffmpegChecked) return _ffmpegPath;
    _ffmpegChecked = true;
    _ffmpegPath = await _findFFmpeg();
    return _ffmpegPath;
  }

  static Future<void> _acquireSlot() async {
    if (_activeJobs < _maxConcurrent) {
      _activeJobs++;
      return;
    }
    final completer = Completer<void>();
    _jobQueue.add(completer);
    await completer.future;
    _activeJobs++;
  }

  static void _releaseSlot() {
    _activeJobs--;
    if (_jobQueue.isNotEmpty) {
      _jobQueue.removeAt(0).complete();
    }
  }

  /// Returns the path to a cached thumbnail for the given video file,
  /// generating it if it doesn't already exist. Returns null on failure.
  static Future<String?> getThumbnail(String videoPath) async {
    // Check memory cache first
    if (_memCache.containsKey(videoPath)) {
      return _memCache[videoPath];
    }

    final cacheDir = await _ensureCacheDir();
    final hash = videoPath.hashCode.toUnsigned(32).toRadixString(16);
    final thumbPath = p.join(cacheDir, 'thumb_$hash.jpg');

    // Check disk cache
    if (File(thumbPath).existsSync()) {
      _memCache[videoPath] = thumbPath;
      return thumbPath;
    }

    // Generate via FFmpeg with concurrency limit
    final ffmpeg = await _getFFmpeg();
    if (ffmpeg == null) return null;

    await _acquireSlot();
    try {
      final result = await Process.run(ffmpeg, [
        '-ss', '1',            // seek BEFORE input (fast keyframe seek)
        '-i', videoPath,
        '-vframes', '1',
        '-vf', 'scale=180:-1', // 180px wide
        '-q:v', '6',           // fast JPEG quality
        '-y',
        thumbPath,
      ]);

      if (result.exitCode == 0 && File(thumbPath).existsSync()) {
        _memCache[videoPath] = thumbPath;
        return thumbPath;
      }
    } catch (e) {
      debugPrint('Thumbnail generation failed: $e');
    } finally {
      _releaseSlot();
    }
    return null;
  }

  /// Pre-generate thumbnails for a list of video paths in parallel.
  static Future<void> pregenerate(List<String> videoPaths) async {
    final futures = <Future>[];
    for (final path in videoPaths) {
      if (_memCache.containsKey(path)) continue;
      futures.add(getThumbnail(path));
    }
    await Future.wait(futures);
  }

  /// Clear the in-memory cache (disk cache persists until temp cleanup).
  static void clearMemoryCache() {
    _memCache.clear();
  }

  static Future<String?> _findFFmpeg() async {
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(which, ['ffmpeg']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final ffmpegName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final local = File('$exeDir${Platform.pathSeparator}$ffmpegName');
    if (await local.exists()) return local.path;

    return null;
  }
}
