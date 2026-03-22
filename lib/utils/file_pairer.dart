// lib/utils/file_pairer.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/video_pair.dart';

/// Scans a directory and pairs front (F) and back (B) dashcam files.
///
/// Naming convention expected:
///   <timestamp>F.<ext>  →  front camera
///   <timestamp>B.<ext>  →  back  camera
///
/// Where timestamp is typically: YYYYMMDD_HHMMSS
/// e.g.  20240315_143022F.mp4  &  20240315_143022B.mp4
class FilePairer {
  static const _videoExtensions = {'.mp4', '.mov', '.avi', '.mkv', '.ts'};

  /// Returns a sorted list of matched [VideoPair]s from [directory].
  /// Unmatched files (only F or only B) are silently ignored.
  static Future<List<VideoPair>> pairFiles(Directory directory) async {
    final frontMap = <String, File>{};
    final backMap  = <String, File>{};

    final entities = await directory.list(recursive: false).toList();

    for (final entity in entities) {
      if (entity is! File) continue;

      final ext  = p.extension(entity.path).toLowerCase();
      if (!_videoExtensions.contains(ext)) continue;

      final name     = p.basenameWithoutExtension(entity.path);
      final lastChar = name.isEmpty ? '' : name[name.length - 1].toUpperCase();

      if (lastChar == 'F') {
        final key = name.substring(0, name.length - 1);
        frontMap[key] = entity;
      } else if (lastChar == 'B') {
        final key = name.substring(0, name.length - 1);
        backMap[key] = entity;
      }
    }

    final pairs = <VideoPair>[];
    for (final key in frontMap.keys) {
      final back = backMap[key];
      if (back == null) continue; // no matching B file

      final ts = _parseTimestamp(key);
      pairs.add(VideoPair(
        id:        key,
        frontFile: frontMap[key]!,
        backFile:  back,
        timestamp: ts ?? DateTime.now(),
      ));
    }

    // Sort chronologically (oldest first)
    pairs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return pairs;
  }

  /// Accepts two separate directories (one for F, one for B).
  static Future<List<VideoPair>> pairFromTwoDirectories(
    Directory frontDir,
    Directory backDir,
  ) async {
    final frontMap = <String, File>{};
    final backMap  = <String, File>{};

    Future<void> scan(Directory dir, Map<String, File> target, String marker) async {
      final entities = await dir.list(recursive: false).toList();
      for (final entity in entities) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_videoExtensions.contains(ext)) continue;
        final name = p.basenameWithoutExtension(entity.path);
        // Key is the whole filename without extension when using separate folders
        target[name] = entity;
      }
    }

    await scan(frontDir, frontMap, 'F');
    await scan(backDir,  backMap,  'B');

    // Try to match by stripping trailing F/B from filenames
    final pairs = <VideoPair>[];
    for (final fKey in frontMap.keys) {
      final rootKey = fKey.endsWith('F') || fKey.endsWith('f')
          ? fKey.substring(0, fKey.length - 1)
          : fKey;

      File? backFile = backMap[rootKey + 'B'] ?? backMap[rootKey + 'b'] ?? backMap[rootKey];
      if (backFile == null) continue;

      final ts = _parseTimestamp(rootKey);
      pairs.add(VideoPair(
        id:        rootKey,
        frontFile: frontMap[fKey]!,
        backFile:  backFile,
        timestamp: ts ?? DateTime.now(),
      ));
    }

    pairs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return pairs;
  }

  /// Parses common dashcam timestamp formats:
  ///   YYYYMMDD_HHMMSS
  ///   YYYY-MM-DD_HH-MM-SS
  ///   YYYYMMDDHHMMSS
  static DateTime? _parseTimestamp(String key) {
    // Normalise separators
    final clean = key.replaceAll(RegExp(r'[-_: ]'), '');

    if (clean.length >= 14) {
      try {
        final year   = int.parse(clean.substring(0, 4));
        final month  = int.parse(clean.substring(4, 6));
        final day    = int.parse(clean.substring(6, 8));
        final hour   = int.parse(clean.substring(8, 10));
        final minute = int.parse(clean.substring(10, 12));
        final second = int.parse(clean.substring(12, 14));
        return DateTime(year, month, day, hour, minute, second);
      } catch (_) {}
    }
    // Fallback: try just YYYYMMDD
    if (clean.length >= 8) {
      try {
        final year  = int.parse(clean.substring(0, 4));
        final month = int.parse(clean.substring(4, 6));
        final day   = int.parse(clean.substring(6, 8));
        return DateTime(year, month, day);
      } catch (_) {}
    }
    return null;
  }
}