// lib/utils/file_pairer.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/dashcam_file.dart';
import '../models/video_pair.dart';
import '../services/dashcam_service.dart';

/// Scans a root drive/folder for videos and intelligently pairs dashcam
/// front/back files while including all other videos as standalone clips.
///
/// Supports:
///   - Dashcam folder structure: video_front/, video_back/, *_lock/
///   - Single folder with F/B suffix: clip_F.mp4 / clip_B.mp4
///   - Recursive nested folder scanning
///   - Any video format (mp4, mkv, avi, ts, webm, flv, wmv, m4v, etc.)
class FilePairer {
  static const _videoExtensions = {
    '.mp4', '.mov', '.avi', '.mkv', '.ts', '.webm', '.flv',
    '.wmv', '.m4v', '.3gp', '.mts', '.m2ts', '.vob', '.ogv',
    '.mpg', '.mpeg', '.divx', '.f4v', '.asf',
  };
  static const _toleranceSeconds = 5;

  /// Check if a file path has a supported video extension.
  static bool isVideoFile(String path) {
    final ext = path.contains('.') ? '.${path.split('.').last.toLowerCase()}' : '';
    return _videoExtensions.contains(ext);
  }

  /// Main entry: scans root directory recursively and returns all video pairs.
  /// Detects dashcam structure, pairs front/back, includes other videos.
  static Future<List<VideoPair>> pairFromRoot(Directory root) async {
    // Check for dashcam folder structure at root level
    final frontDirs = <Directory>[];
    final backDirs  = <Directory>[];

    final rootEntries = await root.list(recursive: false).toList();
    for (final e in rootEntries) {
      if (e is! Directory) continue;
      final name = p.basename(e.path).toLowerCase();
      if (name == 'video_front' || name == 'video_front_lock') {
        frontDirs.add(e);
      } else if (name == 'video_back' || name == 'video_back_lock') {
        backDirs.add(e);
      }
    }

    final hasDashcamStructure = frontDirs.isNotEmpty || backDirs.isNotEmpty;

    if (hasDashcamStructure) {
      // Pair dashcam files from dedicated folders
      final frontFiles = <_TimestampedFile>[];
      final backFiles  = <_TimestampedFile>[];

      for (final dir in frontDirs) {
        final isLock = p.basename(dir.path).toLowerCase().contains('lock');
        frontFiles.addAll(await _scanDirectory(dir, isLock));
      }
      for (final dir in backDirs) {
        final isLock = p.basename(dir.path).toLowerCase().contains('lock');
        backFiles.addAll(await _scanDirectory(dir, isLock));
      }

      final dashcamPairs = _matchByTimestamp(frontFiles, backFiles);

      // Also scan for other videos outside dashcam folders
      final otherVideos = await _scanOtherVideos(root, {
        ...frontDirs.map((d) => d.path),
        ...backDirs.map((d) => d.path),
      });

      return [...dashcamPairs, ...otherVideos]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    // No dashcam structure — scan everything recursively
    return _scanAllVideos(root);
  }

  /// Scan all videos in a directory tree. Tries F/B suffix pairing,
  /// includes everything else as standalone clips.
  static Future<List<VideoPair>> _scanAllVideos(Directory root) async {
    final frontFiles  = <_TimestampedFile>[];
    final backFiles   = <_TimestampedFile>[];
    final otherFiles  = <_TimestampedFile>[];

    final entities = await root.list(recursive: true).toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_videoExtensions.contains(ext)) continue;

      final name = p.basenameWithoutExtension(entity.path);
      final parentDir = p.basename(p.dirname(entity.path)).toLowerCase();

      // Detect camera by parent folder name or filename suffix
      final isInFrontDir = parentDir.contains('front');
      final isInBackDir = parentDir.contains('back');
      final lastChar = name.isEmpty ? '' : name[name.length - 1].toUpperCase();
      // Also check for _f / _b before extension (dashcam pattern)
      final endsWithF = name.toLowerCase().endsWith('_f') ||
          RegExp(r'_f$', caseSensitive: false).hasMatch(name);
      final endsWithB = name.toLowerCase().endsWith('_b') ||
          RegExp(r'_b$', caseSensitive: false).hasMatch(name);

      final ts = _parseTimestamp(name) ?? (await entity.lastModified());

      if (isInFrontDir || endsWithF || (!isInBackDir && lastChar == 'F')) {
        frontFiles.add(_TimestampedFile(entity, ts, false));
      } else if (isInBackDir || endsWithB || lastChar == 'B') {
        backFiles.add(_TimestampedFile(entity, ts, false));
      } else {
        otherFiles.add(_TimestampedFile(entity, ts, false));
      }
    }

    final dashcamPairs = _matchByTimestamp(frontFiles, backFiles);

    // Add other (non-dashcam) videos as standalone front-only clips
    for (final other in otherFiles) {
      dashcamPairs.add(VideoPair(
        id: _formatId(other.timestamp),
        frontFile: other.file,
        timestamp: other.timestamp,
        source: 'local',
      ));
    }

    dashcamPairs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return dashcamPairs;
  }

  /// Scan for videos outside the dashcam folders (other directories + root files).
  static Future<List<VideoPair>> _scanOtherVideos(
      Directory root, Set<String> excludeDirs) async {
    final pairs = <VideoPair>[];

    final entities = await root.list(recursive: true).toList();
    for (final entity in entities) {
      if (entity is! File) continue;

      // Skip files inside dashcam directories
      if (excludeDirs.any((d) => entity.path.startsWith(d))) continue;

      final ext = p.extension(entity.path).toLowerCase();
      if (!_videoExtensions.contains(ext)) continue;

      final name = p.basenameWithoutExtension(entity.path);
      final ts = _parseTimestamp(name) ?? (await entity.lastModified());

      pairs.add(VideoPair(
        id: _formatId(ts),
        frontFile: entity,
        timestamp: ts,
        source: 'local',
      ));
    }
    return pairs;
  }

  /// Scan a directory (non-recursive) for video files.
  static Future<List<_TimestampedFile>> _scanDirectory(
      Directory dir, bool isLock) async {
    final result   = <_TimestampedFile>[];
    final entities = await dir.list(recursive: false).toList();

    for (final entity in entities) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_videoExtensions.contains(ext)) continue;

      final name = p.basenameWithoutExtension(entity.path);
      final ts   = _parseTimestamp(name) ?? (await entity.lastModified());
      result.add(_TimestampedFile(entity, ts, isLock));
    }

    return result;
  }

  /// Match front and back files with ±5 second tolerance.
  /// Unmatched files are included as single-camera pairs.
  static List<VideoPair> _matchByTimestamp(
    List<_TimestampedFile> frontFiles,
    List<_TimestampedFile> backFiles,
  ) {
    final pairs   = <VideoPair>[];
    final usedBack = <int>{};

    for (final front in frontFiles) {
      _TimestampedFile? bestBack;
      int bestBackIdx = -1;
      int bestDiff    = _toleranceSeconds * 1000 + 1; // ms

      for (int i = 0; i < backFiles.length; i++) {
        if (usedBack.contains(i)) continue;
        final diff = front.timestamp
            .difference(backFiles[i].timestamp)
            .inMilliseconds
            .abs();
        if (diff <= _toleranceSeconds * 1000 && diff < bestDiff) {
          bestDiff    = diff;
          bestBack    = backFiles[i];
          bestBackIdx = i;
        }
      }

      if (bestBack != null) {
        usedBack.add(bestBackIdx);
        final syncOffsetMs = front.timestamp
            .difference(bestBack.timestamp)
            .inMilliseconds;
        pairs.add(VideoPair(
          id:          _formatId(front.timestamp),
          frontFile:   front.file,
          backFile:    bestBack.file,
          timestamp:   front.timestamp,
          isLocked:    front.isLock || bestBack.isLock,
          syncOffsetMs: syncOffsetMs,
        ));
      } else {
        // No back match — add as front-only
        pairs.add(VideoPair(
          id:        _formatId(front.timestamp),
          frontFile: front.file,
          backFile:  null,
          timestamp: front.timestamp,
          isLocked:  front.isLock,
        ));
      }
    }

    // Add remaining unmatched back files
    for (int i = 0; i < backFiles.length; i++) {
      if (usedBack.contains(i)) continue;
      final back = backFiles[i];
      pairs.add(VideoPair(
        id:        _formatId(back.timestamp),
        frontFile: null,
        backFile:  back.file,
        timestamp: back.timestamp,
        isLocked:  back.isLock,
      ));
    }

    pairs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return pairs;
  }

  static String _formatId(DateTime ts) =>
      '${ts.year}${_p(ts.month)}${_p(ts.day)}_'
      '${_p(ts.hour)}${_p(ts.minute)}${_p(ts.second)}';

  static String _p(int n) => n.toString().padLeft(2, '0');

  // ── WiFi dashcam file pairing ─────────────────────────────────────────

  /// Pair dashcam files from the WiFi API into VideoPairs.
  static List<VideoPair> pairFromDashcam(List<DashcamFile> files) {
    final frontFiles = <DashcamFile>[];
    final backFiles = <DashcamFile>[];

    for (final file in files) {
      if (file.isFront) {
        frontFiles.add(file);
      } else if (file.isBack) {
        backFiles.add(file);
      } else {
        frontFiles.add(file);
      }
    }

    final baseUrl = DashcamService.baseUrl;
    final pairs = <VideoPair>[];
    final usedBack = <int>{};

    for (final front in frontFiles) {
      final frontTs = front.timestamp ??
          DateTime.fromMillisecondsSinceEpoch(front.createtime * 1000);

      DashcamFile? bestBack;
      int bestBackIdx = -1;
      int bestDiff = _toleranceSeconds * 1000 + 1;

      for (int i = 0; i < backFiles.length; i++) {
        if (usedBack.contains(i)) continue;
        final backTs = backFiles[i].timestamp ??
            DateTime.fromMillisecondsSinceEpoch(backFiles[i].createtime * 1000);
        final diff = frontTs.difference(backTs).inMilliseconds.abs();
        if (diff <= _toleranceSeconds * 1000 && diff < bestDiff) {
          bestDiff = diff;
          bestBack = backFiles[i];
          bestBackIdx = i;
        }
      }

      if (bestBack != null) {
        usedBack.add(bestBackIdx);
        final backTs = bestBack.timestamp ??
            DateTime.fromMillisecondsSinceEpoch(bestBack.createtime * 1000);
        final syncOffsetMs = frontTs.difference(backTs).inMilliseconds;

        pairs.add(VideoPair(
          id: _formatId(frontTs),
          frontUrl: '$baseUrl${front.path}',
          backUrl: '$baseUrl${bestBack.path}',
          timestamp: frontTs,
          isLocked: front.folder == 'emr' || bestBack.folder == 'emr',
          syncOffsetMs: syncOffsetMs,
          source: 'wifi-${front.folder}',
        ));
      } else {
        pairs.add(VideoPair(
          id: _formatId(frontTs),
          frontUrl: '$baseUrl${front.path}',
          timestamp: frontTs,
          isLocked: front.folder == 'emr',
          source: 'wifi-${front.folder}',
        ));
      }
    }

    for (int i = 0; i < backFiles.length; i++) {
      if (usedBack.contains(i)) continue;
      final back = backFiles[i];
      final backTs = back.timestamp ??
          DateTime.fromMillisecondsSinceEpoch(back.createtime * 1000);
      pairs.add(VideoPair(
        id: _formatId(backTs),
        backUrl: '$baseUrl${back.path}',
        timestamp: backTs,
        isLocked: back.folder == 'emr',
        source: 'wifi-${back.folder}',
      ));
    }

    pairs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return pairs;
  }

  /// Parses common dashcam timestamp formats:
  ///   YYYYMMDD_HHMMSS   (most common)
  ///   YYYY-MM-DD_HH-MM-SS
  ///   YYYYMMDDHHMMSS
  static DateTime? _parseTimestamp(String name) {
    final clean = name.replaceAll(RegExp(r'[-_: ]'), '');
    final digits = RegExp(r'\d{14}').firstMatch(clean)?.group(0) ??
                   RegExp(r'\d{8}').firstMatch(clean)?.group(0);
    if (digits == null) return null;

    if (digits.length >= 14) {
      try {
        return DateTime(
          int.parse(digits.substring(0, 4)),
          int.parse(digits.substring(4, 6)),
          int.parse(digits.substring(6, 8)),
          int.parse(digits.substring(8, 10)),
          int.parse(digits.substring(10, 12)),
          int.parse(digits.substring(12, 14)),
        );
      } catch (_) {}
    }
    if (digits.length >= 8) {
      try {
        return DateTime(
          int.parse(digits.substring(0, 4)),
          int.parse(digits.substring(4, 6)),
          int.parse(digits.substring(6, 8)),
        );
      } catch (_) {}
    }
    return null;
  }
}

class _TimestampedFile {
  final File file;
  final DateTime timestamp;
  final bool isLock;
  _TimestampedFile(this.file, this.timestamp, this.isLock);
}
