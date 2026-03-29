// lib/models/video_pair.dart

import 'dart:io';

/// Represents a matched front + back dashcam video pair.
/// Supports both local files (File) and remote dashcam URLs (String).
/// Either front or back can be null if no match was found.
class VideoPair {
  final String id;
  final File? frontFile;
  final File? backFile;
  final String? frontUrl; // HTTP URL for remote dashcam files
  final String? backUrl;  // HTTP URL for remote dashcam files
  final DateTime timestamp;
  final bool isLocked;
  final int syncOffsetMs; // auto-detected offset from timestamp difference
  final String? source;   // 'local', 'wifi-loop', 'wifi-emr', 'wifi-park'

  const VideoPair({
    required this.id,
    this.frontFile,
    this.backFile,
    this.frontUrl,
    this.backUrl,
    required this.timestamp,
    this.isLocked = false,
    this.syncOffsetMs = 0,
    this.source,
  });

  /// Path or URL for the front video (prefers File, falls back to URL).
  String? get frontPath => frontFile?.path ?? frontUrl;

  /// Path or URL for the back video (prefers File, falls back to URL).
  String? get backPath => backFile?.path ?? backUrl;

  bool get hasFront => frontFile != null || frontUrl != null;
  bool get hasBack  => backFile  != null || backUrl  != null;
  bool get isPaired => hasFront && hasBack;

  /// Whether this pair comes from a WiFi dashcam (remote).
  bool get isRemote => source != null && source!.startsWith('wifi');

  @override
  String toString() => 'VideoPair($id, front=$hasFront, back=$hasBack, locked=$isLocked, source=$source)';
}
