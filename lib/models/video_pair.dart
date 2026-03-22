// lib/models/video_pair.dart

import 'dart:io';

/// Represents a matched front + back dashcam video pair.
/// Files are matched by their timestamp prefix (everything before the trailing F/B).
class VideoPair {
  final String id;          // Shared timestamp key, e.g. "20240315_143022"
  final File frontFile;     // e.g. 20240315_143022F.mp4
  final File backFile;      // e.g. 20240315_143022B.mp4
  final DateTime timestamp; // Parsed from filename

  const VideoPair({
    required this.id,
    required this.frontFile,
    required this.backFile,
    required this.timestamp,
  });

  String get frontPath => frontFile.path;
  String get backPath  => backFile.path;

  @override
  String toString() => 'VideoPair($id)';
}