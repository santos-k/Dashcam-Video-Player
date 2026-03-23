// lib/models/video_pair.dart

import 'dart:io';

/// Represents a matched front + back dashcam video pair.
/// Either frontFile or backFile can be null if no match was found.
class VideoPair {
  final String id;
  final File? frontFile;
  final File? backFile;
  final DateTime timestamp;
  final bool isLocked;
  final int syncOffsetMs; // auto-detected offset from timestamp difference

  const VideoPair({
    required this.id,
    this.frontFile,
    this.backFile,
    required this.timestamp,
    this.isLocked = false,
    this.syncOffsetMs = 0,
  });

  String? get frontPath => frontFile?.path;
  String? get backPath  => backFile?.path;

  bool get hasFront => frontFile != null;
  bool get hasBack  => backFile  != null;
  bool get isPaired => hasFront && hasBack;

  @override
  String toString() => 'VideoPair($id, front=$hasFront, back=$hasBack, locked=$isLocked)';
}