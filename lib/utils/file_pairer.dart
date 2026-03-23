// lib/utils/file_pairer.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/video_pair.dart';

/// Scans a root drive/folder for dashcam video folders and pairs them.
///
/// Expected folder structure (auto-detected):
///   <root>/video_front/       ← front camera clips
///   <root>/video_back/        ← back camera clips
///   <root>/video_front_lock/  ← front locked/protected clips
///   <root>/video_back_lock/   ← back locked/protected clips
///
/// Files inside are matched by timestamp with ±5 second tolerance.
/// If only a front OR back file exists, it is still included as a single video.
class FilePairer {
  static const _videoExtensions = {'.mp4', '.mov', '.avi', '.mkv', '.ts', '.MP4', '.MOV', '.AVI', '.MKV', '.TS'};
  static const _toleranceSeconds = 5;

  /// Main entry: scans root directory (e.g. F:\) and returns all pairs.
  static Future<List<VideoPair>> pairFromRoot(Directory root) async {
    // Find all front/back folder combinations
    final frontDirs = <Directory>[];
    final backDirs  = <Directory>[];

    final entries = await root.list(recursive: false).toList();
    for (final e in entries) {
      if (e is! Directory) continue;
      final name = p.basename(e.path).toLowerCase();
      if (name == 'video_front' || name == 'video_front_lock') {
        frontDirs.add(e);
      } else if (name == 'video_back' || name == 'video_back_lock') {
        backDirs.add(e);
      }
    }

    // If no dashcam folders found, try the root itself
    if (frontDirs.isEmpty && backDirs.isEmpty) {
      return pairFromSingleDirectory(root);
    }

    // Collect all front and back files with timestamps
    final frontFiles = <_TimestampedFile>[];
    final backFiles  = <_TimestampedFile>[];

    for (final dir in frontDirs) {
      final isLock = p.basename(dir.path).toLowerCase().contains('lock');
      final files  = await _scanDirectory(dir, isLock);
      frontFiles.addAll(files);
    }
    for (final dir in backDirs) {
      final isLock = p.basename(dir.path).toLowerCase().contains('lock');
      final files  = await _scanDirectory(dir, isLock);
      backFiles.addAll(files);
    }

    return _matchByTimestamp(frontFiles, backFiles);
  }

  /// Fallback: single folder with F/B suffix files.
  static Future<List<VideoPair>> pairFromSingleDirectory(Directory dir) async {
    final frontFiles = <_TimestampedFile>[];
    final backFiles  = <_TimestampedFile>[];

    final entities = await dir.list(recursive: false).toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_videoExtensions.contains(ext) && !_videoExtensions.contains(p.extension(entity.path))) continue;

      final name     = p.basenameWithoutExtension(entity.path);
      final lastChar = name.isEmpty ? '' : name[name.length - 1].toUpperCase();
      final tsStr    = lastChar == 'F' || lastChar == 'B'
          ? name.substring(0, name.length - 1)
          : name;
      final ts = _parseTimestamp(tsStr) ?? DateTime.now();

      if (lastChar == 'F') {
        frontFiles.add(_TimestampedFile(entity, ts, false));
      } else if (lastChar == 'B') {
        backFiles.add(_TimestampedFile(entity, ts, false));
      } else {
        // Unknown suffix — treat as front
        frontFiles.add(_TimestampedFile(entity, ts, false));
      }
    }

    return _matchByTimestamp(frontFiles, backFiles);
  }

  /// Scan a directory and return all video files with parsed timestamps.
  static Future<List<_TimestampedFile>> _scanDirectory(
      Directory dir, bool isLock) async {
    final result   = <_TimestampedFile>[];
    final entities = await dir.list(recursive: false).toList();

    for (final entity in entities) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_videoExtensions.contains(ext) &&
          !_videoExtensions.contains(p.extension(entity.path))) continue;

      final name = p.basenameWithoutExtension(entity.path);
      final ts   = _parseTimestamp(name) ?? DateTime.now();
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

  /// Parses common dashcam timestamp formats:
  ///   YYYYMMDD_HHMMSS   (most common)
  ///   YYYY-MM-DD_HH-MM-SS
  ///   YYYYMMDDHHMMSS
  static DateTime? _parseTimestamp(String name) {
    final clean = name.replaceAll(RegExp(r'[-_: ]'), '');
    // Try digits only from anywhere in the string (some cams prefix with letters)
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
  const _TimestampedFile(this.file, this.timestamp, this.isLock);
}