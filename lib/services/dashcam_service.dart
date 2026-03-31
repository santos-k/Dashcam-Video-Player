// lib/services/dashcam_service.dart
//
// HTTP REST API client for Onelap Wi-Fi dashcam.
// Base: http://192.168.169.1/app/*  (all GET, JSON responses)
// Discovered via Packet Capture Pro HAR analysis.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/dashcam_file.dart';
import '../models/dashcam_state.dart';

class DashcamService {
  DashcamService._();

  /// Configurable IP — defaults to Onelap dashcam address.
  static String ip = '192.168.169.1';
  static String get baseUrl => 'http://$ip';

  static const Duration _cmdTimeout = Duration(seconds: 5);
  static const Duration _downloadTimeout = Duration(seconds: 120);
  static const Duration _thumbTimeout = Duration(seconds: 8);

  // ── Low-level helpers ─────────────────────────────────────────────────

  /// GET a JSON endpoint under /app/ and return parsed body.
  /// Throws on network error or non-200 status.
  static Future<Map<String, dynamic>> _getJson(String path) async {
    final url = '$baseUrl/app/$path';
    debugPrint('DashcamService → GET $url');
    final client = HttpClient()..connectionTimeout = _cmdTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(_cmdTimeout);
      final raw = await response.transform(utf8.decoder).join();
      debugPrint('DashcamService ← [${response.statusCode}] '
          '${raw.length > 500 ? '${raw.substring(0, 500)}…' : raw}');

      // The dashcam sometimes prepends HTTP headers in the body text
      // (e.g. "Content-Length: 31\nConnection: close\n\n{...}")
      // Extract the JSON portion.
      final jsonStr = _extractJson(raw);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Extract the first JSON object from a response that may contain
  /// inline HTTP headers before the actual JSON body.
  static String _extractJson(String raw) {
    final idx = raw.indexOf('{');
    if (idx < 0) return raw;
    return raw.substring(idx);
  }

  /// Check result field — returns true if result == 0 (success).
  static bool _isOk(Map<String, dynamic> json) => json['result'] == 0;

  /// Fetch a raw URL and return bytes (for thumbnails / file downloads).
  static Future<Uint8List> _getBytes(String url,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(timeout);
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close(force: true);
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────

  /// Check if dashcam is reachable. Uses getdeviceattr as a ping.
  static Future<bool> checkConnection() async {
    try {
      final json = await _getJson('getdeviceattr');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  /// Try to reach a specific IP.
  static Future<bool> _probeIp(String testIp) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final url = 'http://$testIp/app/getdeviceattr';
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return true;
    } catch (_) {}
    try {
      final req = await client.getUrl(Uri.parse('http://$testIp/'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode >= 200 && res.statusCode < 500) return true;
    } catch (_) {}
    client.close(force: true);
    return false;
  }

  /// Auto-discover the dashcam by scanning common IPs and the gateway.
  static Future<String?> autoDiscover({
    void Function(String message)? onStatus,
  }) async {
    final gatewayIps = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            gatewayIps.add('${parts[0]}.${parts[1]}.${parts[2]}.1');
            gatewayIps.add('${parts[0]}.${parts[1]}.${parts[2]}.254');
          }
        }
      }
    } catch (_) {}

    final candidates = <String>{
      '192.168.169.1', // Onelap default
      '192.168.1.254', // Novatek fallback
      '192.168.0.1',
      '192.168.1.1',
      '192.168.42.1',
      '192.168.43.1',
      ...gatewayIps,
    };

    onStatus?.call('Scanning ${candidates.length} addresses…');
    debugPrint('DashcamService: auto-discover candidates: $candidates');

    final futures = <Future<String?>>[];
    for (final candidate in candidates) {
      futures.add(() async {
        onStatus?.call('Trying $candidate…');
        final ok = await _probeIp(candidate);
        return ok ? candidate : null;
      }());
    }

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result != null) {
        onStatus?.call('Found dashcam at $result');
        return result;
      }
    }

    onStatus?.call('No dashcam found');
    return null;
  }

  /// Heartbeat — uses getdeviceattr (lightweight, ~6ms).
  static Future<bool> sendHeartbeat() async {
    try {
      final json = await _getJson('getdeviceattr');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  // ── Device info ────────────────────────────────────────────────────────

  /// GET /app/getdeviceattr
  /// Returns: uuid, otaver, softver, hwver, ssid, bssid, camnum, curcamid, wifireboot
  static Future<DashcamDeviceInfo> getDeviceInfo() async {
    final json = await _getJson('getdeviceattr');
    return DashcamDeviceInfo.fromJson(json['info'] as Map<String, dynamic>);
  }

  /// GET /app/getsdinfo
  /// Returns: status, free (MB), total (MB)
  static Future<DashcamStorageInfo> getStorageInfo() async {
    final json = await _getJson('getsdinfo');
    return DashcamStorageInfo.fromJson(json['info'] as Map<String, dynamic>);
  }

  /// GET /app/getmediainfo
  /// Returns: rtsp URL, transport, port
  static Future<DashcamMediaInfo> getMediaInfo() async {
    final json = await _getJson('getmediainfo');
    return DashcamMediaInfo.fromJson(json['info'] as Map<String, dynamic>);
  }

  // ── File operations ────────────────────────────────────────────────────

  /// List ALL files from a folder, handling pagination.
  /// [folder]: 'loop' (normal), 'emr' (emergency), 'park' (parking/timelapse)
  static Future<List<DashcamFile>> listFiles({
    String folder = 'loop',
  }) async {
    final allFiles = <DashcamFile>[];
    int start = 0;
    const int pageSize = 100;

    while (true) {
      final json = await _getJson(
          'getfilelist?folder=$folder&start=$start&end=${start + pageSize}');
      if (!_isOk(json)) break;

      final info = json['info'];
      if (info is! List || info.isEmpty) break;

      final folderData = info[0] as Map<String, dynamic>;
      final totalCount = folderData['count'] as int? ?? 0;
      final files = folderData['files'] as List? ?? [];

      for (final f in files) {
        allFiles.add(DashcamFile.fromJson(f as Map<String, dynamic>, folder));
      }

      // If we got all files or no more pages, stop
      if (allFiles.length >= totalCount || files.length < pageSize) break;
      start += files.length;
    }

    return allFiles;
  }

  /// List files from ALL folder types (loop + emr + event + park).
  static Future<List<DashcamFile>> listAllFiles() async {
    final results = await Future.wait([
      listFiles(folder: 'loop'),
      listFiles(folder: 'emr'),
      listFiles(folder: 'event'),
      listFiles(folder: 'park'),
    ]);
    return [...results[0], ...results[1], ...results[2], ...results[3]];
  }

  /// Get a thumbnail image as bytes.
  /// [filePath]: full path on dashcam, e.g. /mnt/card/video_front/20260329_190645_f.ts
  static Future<Uint8List?> getThumbnail(String filePath) async {
    final url =
        '$baseUrl/app/getthumbnail?file=${Uri.encodeComponent(filePath)}';
    try {
      final bytes = await _getBytes(url, timeout: _thumbTimeout);
      // Verify JPEG (starts with FF D8)
      if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return bytes;
      }
      // Some dashcams return thumbnail with HTTP headers prepended
      // Find JPEG start marker
      for (int i = 0; i < bytes.length - 1; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
          return bytes.sublist(i);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete a file from the dashcam SD card.
  /// [filePath]: full path, e.g. /mnt/card/video_front/20260329_190645_f.ts
  static Future<bool> deleteFile(String filePath) async {
    try {
      final json = await _getJson(
          'deletefile?file=${Uri.encodeComponent(filePath)}');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  /// Capture an instant photo snapshot from the active camera.
  static Future<bool> takeSnapshot() async {
    try {
      final json = await _getJson('snapshot');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  /// Download a file from the dashcam to local storage with progress.
  static Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    required int fileSize,
    void Function(double progress)? onProgress,
  }) async {
    final url = '$baseUrl$remotePath';
    final client = HttpClient()
      ..connectionTimeout = _downloadTimeout
      ..idleTimeout = _downloadTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return false;

      final file = File(localPath);
      final sink = file.openWrite();
      int received = 0;
      final total = fileSize > 0
          ? fileSize
          : (response.contentLength > 0 ? response.contentLength : 1);

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call((received / total).clamp(0.0, 1.0));
      }

      await sink.flush();
      await sink.close();
      return true;
    } catch (e) {
      debugPrint('DashcamService download error: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // ── Recording control ─────────────────────────────────────────────────

  /// Enter recorder mode.
  static Future<bool> enterRecorder() async {
    try {
      final json = await _getJson('enterrecorder');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  /// Start recording (set rec=1).
  static Future<bool> startRecording() async {
    return await setParam('rec', 1);
  }

  /// Stop recording (set rec=0).
  static Future<bool> stopRecording() async {
    return await setParam('rec', 0);
  }

  /// Get current recording duration in seconds.
  static Future<int> getRecDuration() async {
    try {
      final json = await _getJson('getrecduration');
      if (_isOk(json)) {
        return (json['info'] as Map<String, dynamic>)['duration'] as int? ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  // ── Settings ───────────────────────────────────────────────────────────

  /// Get all parameter values.
  /// Returns: [{name: "mic", value: 1}, ...]
  static Future<List<DashcamParam>> getParamValues() async {
    final json = await _getJson('getparamvalue?param=all');
    if (!_isOk(json)) return [];
    final list = json['info'] as List? ?? [];
    return list
        .map((e) => DashcamParam.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get a single parameter value.
  static Future<int?> getParamValue(String param) async {
    try {
      final json = await _getJson('getparamvalue?param=$param');
      if (_isOk(json)) {
        return (json['info'] as Map<String, dynamic>)['value'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Get all parameter item schemas (available options).
  /// Returns: [{name: "mic", items: ["off","on"], index: [0,1]}, ...]
  static Future<List<DashcamParamSchema>> getParamItems() async {
    final json = await _getJson('getparamitems?param=all');
    if (!_isOk(json)) return [];
    final list = json['info'] as List? ?? [];
    return list
        .map((e) => DashcamParamSchema.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Set a parameter value.
  static Future<bool> setParam(String param, int value) async {
    try {
      final json = await _getJson('setparamvalue?param=$param&value=$value');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  // ── Time sync ─────────────────────────────────────────────────────────

  /// Set the dashcam system time.
  static Future<bool> setDateTime(DateTime dt) async {
    final dateStr = '${dt.year}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
    try {
      final json = await _getJson('setsystime?date=$dateStr');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  /// Set the dashcam timezone offset.
  static Future<bool> setTimezone(int offset) async {
    try {
      final json = await _getJson('settimezone?timezone=$offset');
      return _isOk(json);
    } catch (_) {
      return false;
    }
  }

  // ── Camera switch ─────────────────────────────────────────────────────

  /// Switch active camera view: 0 = front, 1 = back.
  static Future<bool> switchCamera(int camId) async {
    return await setParam('switchcam', camId);
  }

  // ── RTSP stream URLs ──────────────────────────────────────────────────

  /// Primary RTSP URL (port 5000 from getmediainfo, TCP transport).
  static String get rtspUrl => 'rtsp://$ip:5000';

  /// All possible RTSP stream URLs to try.
  static List<String> get rtspUrls => [
        'rtsp://$ip:5000',
        'rtsp://$ip:5000/live',
        'rtsp://$ip:5000/0',
        'rtsp://$ip:5000/1',
        'rtsp://$ip',
        'rtsp://$ip:554',
        'http://$ip:5000',
      ];
}
