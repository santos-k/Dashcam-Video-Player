// lib/services/gps_extractor_service.dart
//
// Extracts GPS coordinates from dashcam videos using multiple strategies:
// 1. Companion SRT subtitle files (fastest, most reliable)
// 2. Embedded subtitle streams in the video file
// 3. OCR from video frames — Windows OCR (built-in) or Tesseract (fallback)
//
// Strategy 3 first checks a single frame to detect whether the video has
// a GPS text overlay at all; if not, it skips the rest of the frames.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/gps_point.dart';
import 'log_service.dart';

class GpsExtractorService {
  /// Extract GPS points from a video file.  Tries multiple strategies.
  static Future<List<GpsPoint>> extractGpsPoints(String videoPath) async {
    // Strategy 1: Companion SRT file
    var points = await _tryParseSrt(videoPath);
    if (points.isNotEmpty) {
      appLog('GPS', 'Extracted ${points.length} points from SRT file');
      return points;
    }

    // Strategy 2: Embedded subtitle stream
    points = await _tryExtractEmbeddedSubtitles(videoPath);
    if (points.isNotEmpty) {
      appLog('GPS', 'Extracted ${points.length} points from embedded subtitles');
      return points;
    }

    // Strategy 3: OCR from video frames
    points = await _tryOcr(videoPath);
    if (points.isNotEmpty) {
      appLog('GPS', 'Extracted ${points.length} points via OCR');
    } else {
      appLog('GPS', 'No GPS data found in $videoPath');
    }
    return points;
  }

  // ─── Strategy 1: Companion SRT file ──────────────────────────────────────────

  static Future<List<GpsPoint>> _tryParseSrt(String videoPath) async {
    final base = p.withoutExtension(videoPath);
    for (final srtPath in ['$base.srt', '$base.SRT']) {
      final file = File(srtPath);
      if (await file.exists()) {
        try {
          return _parseSrtContent(await file.readAsString());
        } catch (_) {}
      }
    }
    return [];
  }

  // ─── Strategy 2: Embedded subtitle stream ────────────────────────────────────

  static Future<List<GpsPoint>> _tryExtractEmbeddedSubtitles(
      String videoPath) async {
    final ffmpeg = await _findFFmpeg();
    if (ffmpeg == null) return [];
    final ffprobe = _ffprobeFrom(ffmpeg);

    try {
      final probe = await Process.run(ffprobe, [
        '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-select_streams', 's', videoPath,
      ]);
      if (probe.exitCode != 0) return [];

      final data = jsonDecode(probe.stdout as String) as Map<String, dynamic>;
      final streams = data['streams'] as List?;
      if (streams == null || streams.isEmpty) return [];

      final tempSrt =
          '${Directory.systemTemp.path}/dcgps_${DateTime.now().millisecondsSinceEpoch}.srt';
      final result = await Process.run(ffmpeg, [
        '-i', videoPath, '-map', '0:s:0', '-y', tempSrt,
      ]);
      if (result.exitCode != 0) return [];

      final file = File(tempSrt);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final points = _parseSrtContent(content);
      await file.delete().catchError((_) => file);
      return points;
    } catch (_) {
      return [];
    }
  }

  // ─── Strategy 3: OCR from video frames ───────────────────────────────────────

  static Future<List<GpsPoint>> _tryOcr(String videoPath) async {
    final ffmpeg = await _findFFmpeg();
    if (ffmpeg == null) return [];

    final tempDir = Directory(
        '${Directory.systemTemp.path}/dcgps_ocr_${DateTime.now().millisecondsSinceEpoch}');
    await tempDir.create(recursive: true);

    try {
      // ── Step 1: Quick-check — extract ONE frame and see if GPS text exists ──
      final testFrame = '${tempDir.path}/test.png';
      await Process.run(ffmpeg, [
        '-ss', '2', '-i', videoPath,
        '-vf', _cropFilter,
        '-frames:v', '1', '-q:v', '2', '-y', testFrame,
      ]);

      if (!File(testFrame).existsSync()) return [];

      final testText = await _runOcr(testFrame);
      if (testText == null ||
          _parseGpsFromText(testText, Duration.zero) == null) {
        appLog('GPS', 'No GPS overlay detected in first frame — skipping OCR');
        return [];
      }
      appLog('GPS', 'GPS overlay detected — extracting all frames');

      // ── Step 2: Extract all frames at 5-second intervals ────────────────────
      await Process.run(ffmpeg, [
        '-i', videoPath,
        '-vf', 'fps=1/5,$_cropFilter',
        '-q:v', '2', '-y',
        '${tempDir.path}/f_%04d.png',
      ]);

      // Remove the test frame
      File(testFrame).deleteSync();

      // ── Step 3: Batch OCR all frames ────────────────────────────────────────
      return _batchOcr(tempDir.path);
    } catch (e) {
      appLog('GPS', 'OCR error: $e');
      return [];
    } finally {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  }

  /// FFmpeg crop+scale filter for the bottom-left GPS text region.
  /// Crop: left 30%, bottom 7% of frame — then upscale 3× for OCR accuracy.
  static const _cropFilter =
      'crop=iw*0.3:ih*0.07:0:ih-ih*0.07,scale=iw*3:ih*3:flags=lanczos';

  /// Run OCR on a single image file.  Returns recognised text or null.
  static Future<String?> _runOcr(String imagePath) async {
    if (Platform.isWindows) {
      final text = await _windowsOcr(imagePath);
      if (text != null) return text;
    }
    // Fallback: try Tesseract CLI
    return _tesseractOcr(imagePath);
  }

  /// Batch-OCR every PNG in [dirPath].  Returns parsed GPS points.
  static Future<List<GpsPoint>> _batchOcr(String dirPath) async {
    if (Platform.isWindows) {
      final pts = await _windowsOcrBatch(dirPath);
      if (pts.isNotEmpty) return pts;
    }
    return _tesseractOcrBatch(dirPath);
  }

  // ─── Windows built-in OCR (no install required on Win 10/11) ─────────────────

  static Future<String?> _windowsOcr(String imagePath) async {
    final absPath = File(imagePath).absolute.path.replaceAll('/', '\\');
    final script = _buildPsOcrScript("'$absPath'");
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      );
      if (result.exitCode == 0) {
        final text = (result.stdout as String).trim();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<GpsPoint>> _windowsOcrBatch(String dirPath) async {
    final absDir = Directory(dirPath).absolute.path.replaceAll('/', '\\');

    // Write batch OCR PowerShell script to a temp .ps1 file
    final ps1 = File('$absDir\\ocr_batch.ps1');
    await ps1.writeAsString(_batchPsScript);

    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ps1.path,
        '-Dir', absDir,
      ]);

      if (result.exitCode != 0) {
        appLog('GPS', 'Windows OCR batch failed: ${result.stderr}');
        return [];
      }

      final points = <GpsPoint>[];
      final lines = (result.stdout as String).split('\n');
      for (final line in lines) {
        final sep = line.indexOf('|');
        if (sep < 0) continue;
        final name = line.substring(0, sep).trim(); // e.g. "f_0001"
        final text = line.substring(sep + 1).trim();

        // Frame index (1-based) → timestamp
        final idx = int.tryParse(name.replaceAll(RegExp(r'[^0-9]'), ''));
        if (idx == null) continue;
        final ts = Duration(seconds: (idx - 1) * 5);

        final pt = _parseGpsFromText(text, ts);
        if (pt != null) points.add(pt);
      }
      return points;
    } catch (e) {
      appLog('GPS', 'Windows OCR error: $e');
      return [];
    } finally {
      ps1.deleteSync();
    }
  }

  /// PowerShell one-liner to OCR a single image via Windows.Media.Ocr.
  static String _buildPsOcrScript(String pathExpr) {
    return r'''
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Storage.StorageFile,Windows.Foundation,ContentType=WindowsRuntime]

$asTask=([System.WindowsRuntimeSystemExtensions].GetMethods()|?{$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'})[0]
function Await($t,$r){$a=$asTask.MakeGenericMethod($r);$n=$a.Invoke($null,@($t));$n.Wait(-1)|Out-Null;$n.Result}

$f=Await([Windows.Storage.StorageFile]::GetFileFromPathAsync(''' +
        pathExpr +
        r'''))([Windows.Storage.StorageFile])
$s=Await($f.OpenAsync([Windows.Storage.FileAccessMode]::Read))([Windows.Storage.Streams.IRandomAccessStream])
$d=Await([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($s))([Windows.Graphics.Imaging.BitmapDecoder])
$b=Await($d.GetSoftwareBitmapAsync())([Windows.Graphics.Imaging.SoftwareBitmap])
$e=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$r=Await($e.RecognizeAsync($b))([Windows.Media.Ocr.OcrResult])
$s.Dispose()
Write-Output $r.Text
''';
  }

  /// PowerShell batch script — processes all PNGs in a directory.
  static const _batchPsScript = r'''
param([string]$Dir)

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [void][Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.SoftwareBitmap,Windows.Foundation,ContentType=WindowsRuntime]
    [void][Windows.Storage.StorageFile,Windows.Foundation,ContentType=WindowsRuntime]
} catch {
    Write-Error "Windows OCR not available"
    exit 1
}

$asTask=([System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object{$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'})[0]
function Await($t,$r){$a=$asTask.MakeGenericMethod($r);$n=$a.Invoke($null,@($t));$n.Wait(-1)|Out-Null;$n.Result}

$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if($null -eq $engine){Write-Error "OCR engine null";exit 1}

Get-ChildItem "$Dir\*.png" | Sort-Object Name | ForEach-Object {
    try {
        $sf=Await([Windows.Storage.StorageFile]::GetFileFromPathAsync($_.FullName))([Windows.Storage.StorageFile])
        $st=Await($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read))([Windows.Storage.Streams.IRandomAccessStream])
        $dc=Await([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st))([Windows.Graphics.Imaging.BitmapDecoder])
        $bm=Await($dc.GetSoftwareBitmapAsync())([Windows.Graphics.Imaging.SoftwareBitmap])
        $re=Await($engine.RecognizeAsync($bm))([Windows.Media.Ocr.OcrResult])
        $tx=($re.Text -replace "`n"," " -replace "`r"," ").Trim()
        Write-Output "$($_.BaseName)|$tx"
        $st.Dispose()
    } catch {
        Write-Output "$($_.BaseName)|"
    }
}
''';

  // ─── Tesseract fallback (non-Windows or if Windows OCR fails) ────────────────

  static Future<String?> _tesseractOcr(String imagePath) async {
    final tesseract = await _findTesseract();
    if (tesseract == null) return null;
    try {
      final result = await Process.run(tesseract, [
        imagePath, 'stdout', '--psm', '6',
      ]);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return null;
  }

  static Future<List<GpsPoint>> _tesseractOcrBatch(String dirPath) async {
    final tesseract = await _findTesseract();
    if (tesseract == null) return [];

    final dir = Directory(dirPath);
    final frames =
        await dir.list().where((f) => f.path.endsWith('.png')).toList();
    frames.sort((a, b) => a.path.compareTo(b.path));

    final points = <GpsPoint>[];
    for (var i = 0; i < frames.length; i++) {
      final ts = Duration(seconds: i * 5);
      try {
        final result = await Process.run(tesseract, [
          frames[i].path, 'stdout', '--psm', '6',
        ]);
        if (result.exitCode == 0) {
          final pt = _parseGpsFromText(result.stdout as String, ts);
          if (pt != null) points.add(pt);
        }
      } catch (_) {}
    }
    return points;
  }

  // ─── SRT parsing ─────────────────────────────────────────────────────────────

  static List<GpsPoint> _parseSrtContent(String content) {
    final points = <GpsPoint>[];
    final gpsRe = RegExp(
        r'([NS])\s*(\d+\.?\d+)\s+([EW])\s*(\d+\.?\d+)',
        caseSensitive: false);
    final timeRe = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})');
    final speedRe = RegExp(r'(\d+)\s*KM/H', caseSensitive: false);

    for (final block in content.split(RegExp(r'\r?\n\s*\r?\n'))) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      if (lines.length < 2) continue;

      Duration? ts;
      for (final line in lines) {
        final m = timeRe.firstMatch(line);
        if (m != null) {
          ts = Duration(
            hours: int.parse(m.group(1)!),
            minutes: int.parse(m.group(2)!),
            seconds: int.parse(m.group(3)!),
            milliseconds: int.parse(m.group(4)!),
          );
          break;
        }
      }
      if (ts == null) continue;

      final fullText = lines.join(' ');
      final gpsMatch = gpsRe.firstMatch(fullText);
      if (gpsMatch == null) continue;

      var lat = double.tryParse(gpsMatch.group(2)!);
      var lon = double.tryParse(gpsMatch.group(4)!);
      if (lat == null || lon == null || (lat == 0 && lon == 0)) continue;

      if (gpsMatch.group(1)!.toUpperCase() == 'S') lat = -lat;
      if (gpsMatch.group(3)!.toUpperCase() == 'W') lon = -lon;

      double? speed;
      final spdMatch = speedRe.firstMatch(fullText);
      if (spdMatch != null) speed = double.tryParse(spdMatch.group(1)!);

      points.add(GpsPoint(timestamp: ts, lat: lat, lon: lon, speed: speed));
    }
    return points;
  }

  /// Parse GPS from OCR text output.
  static GpsPoint? _parseGpsFromText(String text, Duration timestamp) {
    final gpsRe = RegExp(
        r'([NS])\s*(\d+\.?\d+)\s+([EW])\s*(\d+\.?\d+)',
        caseSensitive: false);
    final speedRe = RegExp(r'(\d+)\s*KM/H', caseSensitive: false);

    final match = gpsRe.firstMatch(text);
    if (match == null) return null;

    var lat = double.tryParse(match.group(2)!);
    var lon = double.tryParse(match.group(4)!);
    if (lat == null || lon == null || (lat == 0 && lon == 0)) return null;

    if (match.group(1)!.toUpperCase() == 'S') lat = -lat;
    if (match.group(3)!.toUpperCase() == 'W') lon = -lon;

    double? speed;
    final spdMatch = speedRe.firstMatch(text);
    if (spdMatch != null) speed = double.tryParse(spdMatch.group(1)!);

    return GpsPoint(timestamp: timestamp, lat: lat, lon: lon, speed: speed);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  static Future<String?> _findFFmpeg() async {
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(which, ['ffmpeg']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final local = File('$exeDir${Platform.pathSeparator}$name');
    if (await local.exists()) return local.path;
    return null;
  }

  static String _ffprobeFrom(String ffmpegPath) {
    final dir = File(ffmpegPath).parent.path;
    final name = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    return '$dir${Platform.pathSeparator}$name';
  }

  static Future<String?> _findTesseract() async {
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(which, ['tesseract']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }
}
