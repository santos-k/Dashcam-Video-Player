// lib/services/export_service.dart
//
// Windows export using system FFmpeg (must be on PATH or in app directory).
// Download FFmpeg from https://ffmpeg.org/download.html and add to PATH.

import 'dart:convert';
import 'dart:io';
import '../models/video_pair.dart';
import '../models/layout_config.dart';

class ExportService {
  /// Returns true on success.
  static Future<bool> exportPair({
    required VideoPair pair,
    required LayoutConfig layout,
    required int syncOffsetMs,
    required String outputPath,
    (double, double)? pipPosition,
    void Function(double progress)? onProgress,
  }) async {
    // Find FFmpeg
    final ffmpeg = await _findFFmpeg();
    if (ffmpeg == null) {
      return false;
    }

    // Get duration for progress estimation
    Duration? duration;
    try {
      duration = await _probeDuration(ffmpeg, pair.frontPath ?? pair.backPath!);
    } catch (_) {}

    final args = _buildArgs(pair, layout, syncOffsetMs, outputPath, pipPosition);

    final process = await Process.start(ffmpeg, args);

    // Parse stderr for time= progress
    process.stderr.transform(const SystemEncoding().decoder).listen((chunk) {
      if (duration == null || duration!.inSeconds == 0) return;
      final match = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(chunk);
      if (match != null) {
        final h   = int.parse(match.group(1)!);
        final m   = int.parse(match.group(2)!);
        final s   = double.parse(match.group(3)!);
        final sec = h * 3600 + m * 60 + s;
        final p   = (sec / duration!.inSeconds).clamp(0.0, 0.99);
        onProgress?.call(p);
      }
    });

    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      onProgress?.call(1.0);
      return true;
    }
    return false;
  }

  static List<String> _buildArgs(
    VideoPair pair,
    LayoutConfig layout,
    int syncOffsetMs,
    String outputPath,
    (double, double)? pipPosition,
  ) {
    // Sync offsets
    final frontDelay = syncOffsetMs < 0
        ? (-syncOffsetMs / 1000.0).toStringAsFixed(3)
        : '0';
    final backDelay = syncOffsetMs > 0
        ? (syncOffsetMs / 1000.0).toStringAsFixed(3)
        : '0';

    // Single video (no front or no back, or front/back only layout)
    if (!pair.isPaired ||
        layout.mode == LayoutMode.frontOnly ||
        layout.mode == LayoutMode.backOnly) {
      final input = layout.mode == LayoutMode.backOnly
          ? (pair.backPath ?? pair.frontPath!)
          : (pair.frontPath ?? pair.backPath!);
      return ['-i', input, '-c:v', 'libx264', '-crf', '23',
              '-preset', 'fast', '-c:a', 'aac', '-y', outputPath];
    }

    final filter = _filterGraph(layout, pipPosition);

    return [
      '-itsoffset', frontDelay,
      '-i', pair.frontPath!,
      '-itsoffset', backDelay,
      '-i', pair.backPath!,
      '-filter_complex', filter,
      '-map', '[out]',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-crf', '23',
      '-preset', 'fast',
      '-c:a', 'aac',
      '-y',
      outputPath,
    ];
  }

  static String _filterGraph(LayoutConfig layout, (double, double)? pipPosition) {
    switch (layout.mode) {
      case LayoutMode.sideBySide:
        return '[0:v]scale=960:540:force_original_aspect_ratio=decrease,'
            'pad=960:540:(ow-iw)/2:(oh-ih)/2:color=black[v0];'
            '[1:v]scale=960:540:force_original_aspect_ratio=decrease,'
            'pad=960:540:(ow-iw)/2:(oh-ih)/2:color=black[v1];'
            '[v0][v1]hstack=inputs=2[out]';
      case LayoutMode.stacked:
        return '[0:v]scale=1920:540:force_original_aspect_ratio=decrease,'
            'pad=1920:540:(ow-iw)/2:(oh-ih)/2:color=black[v0];'
            '[1:v]scale=1920:540:force_original_aspect_ratio=decrease,'
            'pad=1920:540:(ow-iw)/2:(oh-ih)/2:color=black[v1];'
            '[v0][v1]vstack=inputs=2[out]';
      case LayoutMode.pip:
        final mainIdx = layout.pipPrimary == PipPrimary.front ? 0 : 1;
        final pipIdx  = layout.pipPrimary == PipPrimary.front ? 1 : 0;
        final pos     = _pipPos(layout, pipPosition);
        return '[$mainIdx:v]scale=1920:1080:force_original_aspect_ratio=decrease,'
            'pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black[main];'
            '[$pipIdx:v]scale=480:270[pip];'
            '[main][pip]overlay=${pos[0]}:${pos[1]}[out]';
      case LayoutMode.frontOnly:
      case LayoutMode.backOnly:
        // Single video — no filter graph needed, handled by _buildArgs
        return '[0:v]scale=1920:1080:force_original_aspect_ratio=decrease,'
            'pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black[out]';
    }
  }

  static List<String> _pipPos(LayoutConfig layout, (double, double)? pipPosition) {
    // Use actual dragged position if available
    if (pipPosition != null && pipPosition.$1 >= 0 && pipPosition.$2 >= 0) {
      const mainW = 1920;
      const mainH = 1080;
      const pipW  = 480;
      const pipH  = 270;
      const margin = 4;
      final rangeX = mainW - pipW - margin * 2;
      final rangeY = mainH - pipH - margin * 2;
      final x = (margin + pipPosition.$1 * rangeX).round();
      final y = (margin + pipPosition.$2 * rangeY).round();
      return ['$x', '$y'];
    }

    // Fallback to alignment-based position
    final x = switch (layout.pipHAlign) {
      PipHAlign.left   => '20',
      PipHAlign.center => '(1920-480)/2',
      PipHAlign.right  => '1920-480-20',
    };
    final y = switch (layout.pipVAlign) {
      PipVAlign.top    => '20',
      PipVAlign.center => '(1080-270)/2',
      PipVAlign.bottom => '1080-270-20',
    };
    return [x, y];
  }

  /// Try to locate ffmpeg — system PATH first, then next to the running exe.
  static Future<String?> _findFFmpeg() async {
    // 1. Check system PATH
    try {
      final which  = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(which, ['ffmpeg']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}

    // 2. Check next to the running executable
    final exeDir     = File(Platform.resolvedExecutable).parent.path;
    final ffmpegName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final local      = File('$exeDir${Platform.pathSeparator}$ffmpegName');
    if (await local.exists()) return local.path;

    return null;
  }

  /// Extract GPS coordinates from dashcam video metadata via ffprobe.
  /// Returns (latitude, longitude) or null if not available.
  /// Supports: ISO 6709 format tags, and embedded text GPS data in .ts streams
  /// (format: "YYYY/MM/DD HH:MM:SS N:lat E:lon ...").
  static Future<(double, double)?> extractGPS(String videoPath) async {
    final ffmpeg = await _findFFmpeg();
    if (ffmpeg == null) return null;

    final exeDir      = File(ffmpeg).parent.path;
    final ffprobeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    final ffprobe     = '$exeDir${Platform.pathSeparator}$ffprobeName';

    try {
      final result = await Process.run(ffprobe, [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        videoPath,
      ]);
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final tags = (data['format']?['tags'] as Map<String, dynamic>?) ?? {};

        // Try common GPS tag names used by dashcams (ISO 6709 / Apple / Android)
        final loc = tags['location']        as String? ??
                    tags['location-eng']    as String? ??
                    tags['com.apple.quicktime.location.ISO6709'] as String?;
        if (loc != null) {
          // ISO 6709: ±DD.DDDD±DDD.DDDD/
          final match = RegExp(r'([+-]?\d+\.\d+)([+-]\d+\.\d+)').firstMatch(loc);
          if (match != null) {
            final lat = double.tryParse(match.group(1)!);
            final lon = double.tryParse(match.group(2)!);
            if (lat != null && lon != null) return (lat, lon);
          }
        }
      }
    } catch (_) {}

    // Fallback: parse embedded GPS text from .ts file binary data.
    // Dashcam .ts files often embed per-second GPS as text like:
    //   "2026/03/30 10:25:08 N:24.503310 E:84.859970 ..."
    try {
      final coords = await _extractGPSFromTsStream(videoPath);
      if (coords != null) return coords;
    } catch (_) {}

    return null;
  }

  /// Extract GPS from .ts file by reading binary data for embedded text GPS.
  /// Returns the first valid coordinate pair found.
  static Future<(double, double)?> _extractGPSFromTsStream(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;
    final fileSize = await file.length();

    // Read the last portion of the file where GPS text is typically embedded
    // (dashcam .ts files embed GPS data towards the end of the file)
    final readSize = fileSize < 2 * 1024 * 1024 ? fileSize : 2 * 1024 * 1024;
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(fileSize - readSize);
      final bytes = await raf.read(readSize);
      // Decode as ASCII, ignoring non-printable characters
      final text = String.fromCharCodes(
        bytes.where((b) => b >= 0x20 && b < 0x7F || b == 0x0A || b == 0x0D),
      );

      // Pattern: "N:lat E:lon" or "S:lat W:lon" (Onelap dashcam format)
      final re = RegExp(r'([NS]):(\d+\.\d+)\s+([EW]):(\d+\.\d+)');
      final match = re.firstMatch(text);
      if (match != null) {
        var lat = double.tryParse(match.group(2)!);
        var lon = double.tryParse(match.group(4)!);
        if (lat != null && lon != null && lat != 0 && lon != 0) {
          if (match.group(1) == 'S') lat = -lat;
          if (match.group(3) == 'W') lon = -lon;
          return (lat, lon);
        }
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  /// Extract all GPS points from a video for synced map tracking.
  /// Returns list of (timestamp_seconds, latitude, longitude) entries.
  /// Supports .ts files with embedded per-second GPS data.
  static Future<List<(double, double, double)>?> extractGPSTrack(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;
    final fileSize = await file.length();

    try {
      // Read the last portion of the file
      final readSize = fileSize < 4 * 1024 * 1024 ? fileSize : 4 * 1024 * 1024;
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(fileSize - readSize);
        final bytes = await raf.read(readSize);
        final text = String.fromCharCodes(
          bytes.where((b) => b >= 0x20 && b < 0x7F || b == 0x0A || b == 0x0D),
        );

        // Pattern: "YYYY/MM/DD HH:MM:SS N:lat E:lon speed"
        final re = RegExp(
          r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\s+([NS]):(\d+\.\d+)\s+([EW]):(\d+\.\d+)\s+(\d+\.\d+)',
        );
        final matches = re.allMatches(text).toList();
        if (matches.isEmpty) return null;

        // Parse the first timestamp to compute relative offsets
        DateTime? baseTime;
        final track = <(double, double, double)>[];
        for (final m in matches) {
          final timeParts = m.group(1)!.split(RegExp(r'[/ :]'));
          if (timeParts.length < 6) continue;
          final dt = DateTime(
            int.parse(timeParts[0]), int.parse(timeParts[1]),
            int.parse(timeParts[2]), int.parse(timeParts[3]),
            int.parse(timeParts[4]), int.parse(timeParts[5]),
          );
          baseTime ??= dt;
          final secs = dt.difference(baseTime).inMilliseconds / 1000.0;
          var lat = double.tryParse(m.group(3)!);
          var lon = double.tryParse(m.group(5)!);
          if (lat == null || lon == null) continue;
          if (m.group(2) == 'S') lat = -lat;
          if (m.group(4) == 'W') lon = -lon;
          if (lat == 0 && lon == 0) continue;
          track.add((secs, lat, lon));
        }
        return track.isEmpty ? null : track;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Use ffprobe to get video duration. Public for clip duration probing.
  static Future<Duration?> probeDuration(String videoPath) async {
    final ffmpeg = await _findFFmpeg();
    if (ffmpeg == null) return null;
    return _probeDuration(ffmpeg, videoPath);
  }

  static Future<Duration> _probeDuration(String ffmpeg, String videoPath) async {
    final exeDir     = File(ffmpeg).parent.path;
    final ffprobeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    final ffprobe    = '$exeDir${Platform.pathSeparator}$ffprobeName';
    final result  = await Process.run(ffprobe, [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      videoPath,
    ]);
    final secs = double.tryParse((result.stdout as String).trim()) ?? 0;
    return Duration(milliseconds: (secs * 1000).round());
  }
}