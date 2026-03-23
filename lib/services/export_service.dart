// lib/services/export_service.dart

import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/video_pair.dart';
import '../models/layout_config.dart';

class ExportService {
  /// Export both videos composited into a single file.
  ///
  /// [onProgress] fires with values 0.0–1.0.
  /// Returns the output file path, or null on failure.
  static Future<String?> exportPair({
    required VideoPair pair,
    required LayoutConfig layout,
    required int syncOffsetMs,
    void Function(double)? onProgress,
  }) async {
    final outDir  = await getApplicationDocumentsDirectory();
    final outPath = p.join(outDir.path, 'dashcam_export_${pair.id}.mp4');

    // Build FFmpeg filter for the chosen layout
    final filter = _buildFilterGraph(layout, syncOffsetMs);

    // Delay inputs according to sync offset
    final frontDelay = syncOffsetMs < 0 ? (-syncOffsetMs / 1000.0).toStringAsFixed(3) : '0';
    final backDelay  = syncOffsetMs > 0 ? (syncOffsetMs  / 1000.0).toStringAsFixed(3) : '0';

    final cmd = [
      '-itsoffset', frontDelay,
      '-i', '"${pair.frontPath}"',
      '-itsoffset', backDelay,
      '-i', '"${pair.backPath}"',
      '-filter_complex', '"$filter"',
      '-map', '"[out]"',
      '-map', '0:a?',   // optional audio from front
      '-c:v', 'libx264',
      '-crf', '23',
      '-preset', 'fast',
      '-c:a', 'aac',
      '-y',             // overwrite
      '"$outPath"',
    ].join(' ');

    // Listen to statistics for progress
    FFmpegKitConfig.enableStatisticsCallback((stats) {
      // Progress is approximated via time processed; no total duration available
      // Estimate using a 5-minute cap for dashcam clips
      final processed = stats.getTime() / 1000.0; // seconds
      final estimate  = (processed / 300.0).clamp(0.0, 0.99);
      onProgress?.call(estimate);
    });

    final session    = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    FFmpegKitConfig.enableStatisticsCallback(null);

    if (ReturnCode.isSuccess(returnCode)) {
      onProgress?.call(1.0);
      return outPath;
    } else {
      final logs = await session.getAllLogsAsString();
      // ignore: avoid_print
      print('[ExportService] FFmpeg error:\n$logs');
      return null;
    }
  }

  static String _buildFilterGraph(LayoutConfig layout, int syncOffsetMs) {
    switch (layout.mode) {
      case LayoutMode.sideBySide:
        // Scale both to 960×540, join horizontally → 1920×540
        return '[0:v]scale=960:540[v0];'
            '[1:v]scale=960:540[v1];'
            '[v0][v1]hstack=inputs=2[out]';

      case LayoutMode.stacked:
        // Scale both to 1920×540, join vertically → 1920×1080
        return '[0:v]scale=1920:540[v0];'
            '[1:v]scale=1920:540[v1];'
            '[v0][v1]vstack=inputs=2[out]';

      case LayoutMode.pip:
        final isPrimFront = layout.pipPrimary == PipPrimary.front;
        final mainIdx     = isPrimFront ? 0 : 1;
        final pipIdx      = isPrimFront ? 1 : 0;

        final (x, y) = _pipPosition(layout.pipCorner);

        // Main video at 1920×1080; PIP at 480×270 overlaid in chosen corner
        return '[$mainIdx:v]scale=1920:1080[main];'
            '[$pipIdx:v]scale=480:270[pip];'
            '[main][pip]overlay=$x:$y[out]';
    }
  }

  static (String, String) _pipPosition(PipCorner corner) {
    // Assuming 1920×1080 main, 480×270 pip, 20px margin
    switch (corner) {
      case PipCorner.topLeft:     return ('20',             '20');
      case PipCorner.topRight:    return ('1920-480-20',    '20');
      case PipCorner.bottomLeft:  return ('20',             '1080-270-20');
      case PipCorner.bottomRight: return ('1920-480-20',    '1080-270-20');
    }
  }
}