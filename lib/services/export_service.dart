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
      duration = await _probeDuration(ffmpeg, pair.frontFile?.path ?? pair.backFile!.path);
    } catch (_) {}

    final args = _buildArgs(pair, layout, syncOffsetMs, outputPath);

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
  ) {
    // Sync offsets
    final frontDelay = syncOffsetMs < 0
        ? (-syncOffsetMs / 1000.0).toStringAsFixed(3)
        : '0';
    final backDelay = syncOffsetMs > 0
        ? (syncOffsetMs / 1000.0).toStringAsFixed(3)
        : '0';

    // Single video (no front or no back)
    if (!pair.isPaired) {
      final input = pair.frontFile?.path ?? pair.backFile!.path;
      return ['-i', input, '-c:v', 'libx264', '-crf', '23',
              '-preset', 'fast', '-c:a', 'aac', '-y', outputPath];
    }

    final filter = _filterGraph(layout);

    return [
      '-itsoffset', frontDelay,
      '-i', pair.frontFile!.path,
      '-itsoffset', backDelay,
      '-i', pair.backFile!.path,
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

  static String _filterGraph(LayoutConfig layout) {
    switch (layout.mode) {
      case LayoutMode.sideBySide:
        return '[0:v]scale=960:540[v0];[1:v]scale=960:540[v1];[v0][v1]hstack=inputs=2[out]';
      case LayoutMode.stacked:
        return '[0:v]scale=1920:540[v0];[1:v]scale=1920:540[v1];[v0][v1]vstack=inputs=2[out]';
      case LayoutMode.pip:
        final mainIdx = layout.pipPrimary == PipPrimary.front ? 0 : 1;
        final pipIdx  = layout.pipPrimary == PipPrimary.front ? 1 : 0;
        final pos     = _pipPos(layout);
        return '[$mainIdx:v]scale=1920:1080[main];'
            '[$pipIdx:v]scale=480:270[pip];'
            '[main][pip]overlay=${pos[0]}:${pos[1]}[out]';
    }
  }

  static List<String> _pipPos(LayoutConfig layout) {
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
      if (result.exitCode != 0) return null;

      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final tags = (data['format']?['tags'] as Map<String, dynamic>?) ?? {};

      // Try common GPS tag names used by dashcams (ISO 6709 / Apple / Android)
      final loc = tags['location']        as String? ??
                  tags['location-eng']    as String? ??
                  tags['com.apple.quicktime.location.ISO6709'] as String?;
      if (loc == null) return null;

      // ISO 6709: ±DD.DDDD±DDD.DDDD/
      final match = RegExp(r'([+-]?\d+\.\d+)([+-]\d+\.\d+)').firstMatch(loc);
      if (match == null) return null;

      final lat = double.tryParse(match.group(1)!);
      final lon = double.tryParse(match.group(2)!);
      if (lat == null || lon == null) return null;

      return (lat, lon);
    } catch (_) {
      return null;
    }
  }

  /// Use ffprobe to get video duration.
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