// lib/models/dashcam_file.dart
//
// Represents a file on the Onelap dashcam SD card.
// Parsed from GET /app/getfilelist JSON response.

import '../services/dashcam_service.dart';

class DashcamFile {
  /// Full path on dashcam, e.g. /mnt/card/video_front/20260329_190645_f.ts
  final String path;

  /// Filename only, e.g. 20260329_190645_f.ts
  final String name;

  /// File size in bytes.
  final int size;

  /// Unix timestamp (seconds).
  final int createtime;

  /// Human-readable time string, e.g. "20260329190645".
  final String createtimestr;

  /// Folder type: "loop" (normal), "emr" (emergency), "park" (parking/timelapse).
  final String folder;

  /// File type from API (2 = video).
  final int type;

  /// Parsed timestamp.
  final DateTime? timestamp;

  const DashcamFile({
    required this.path,
    required this.name,
    required this.size,
    this.createtime = 0,
    this.createtimestr = '',
    this.folder = 'loop',
    this.type = 2,
    this.timestamp,
  });

  // ── Derived properties ────────────────────────────────────────────────

  /// Whether this is a front camera file.
  bool get isFront => name.contains('_f.') || path.contains('video_front');

  /// Whether this is a back camera file.
  bool get isBack => name.contains('_b.') || path.contains('video_back');

  /// Whether this is a timelapse/parking file.
  bool get isTimelapse => name.contains('_tlp_');

  /// Camera label for display.
  String get cameraLabel => isFront ? 'Front' : (isBack ? 'Back' : 'Unknown');

  /// Folder label for display.
  String get folderLabel => switch (folder) {
        'loop' => 'Normal',
        'emr' => 'Emergency',
        'event' => 'Event',
        'park' => 'Parking',
        _ => folder,
      };

  bool get isVideo {
    final lower = name.toLowerCase();
    return lower.endsWith('.ts') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.avi');
  }

  bool get isPhoto {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  String get displaySize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// HTTP URL to download this file from the dashcam.
  String get downloadUrl => '${DashcamService.baseUrl}$path';

  /// The matching timestamp key for pairing front/back files.
  /// Extracts "20260329_190645" from "20260329_190645_f.ts".
  String get pairingKey {
    // Remove folder prefix, extension, and camera suffix
    final base = name.replaceAll(RegExp(r'\.[^.]+$'), ''); // strip extension
    // Remove _f, _b, _tlp_f, _tlp_b suffixes
    return base
        .replaceAll(RegExp(r'_tlp_[fb]$'), '')
        .replaceAll(RegExp(r'_[fb]$'), '');
  }

  // ── Factory ───────────────────────────────────────────────────────────

  /// Parse from a file entry in the getfilelist JSON response.
  factory DashcamFile.fromJson(Map<String, dynamic> json, String folder) {
    final path = json['name'] as String? ?? '';
    final fileName = path.contains('/')
        ? path.split('/').last
        : path;
    final timeStr = json['createtimestr'] as String? ?? '';

    return DashcamFile(
      path: path,
      name: fileName,
      size: json['size'] as int? ?? 0,
      createtime: json['createtime'] as int? ?? 0,
      createtimestr: timeStr,
      folder: folder,
      type: json['type'] as int? ?? 2,
      timestamp: _parseTimestamp(timeStr),
    );
  }

  static DateTime? _parseTimestamp(String timeStr) {
    if (timeStr.isEmpty) return null;
    // Format: "20260329190645" → 2026-03-29 19:06:45
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})')
        .firstMatch(timeStr);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'DashcamFile($name, $displaySize, $folder)';
}
