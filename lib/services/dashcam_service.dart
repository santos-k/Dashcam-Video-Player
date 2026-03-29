// lib/services/dashcam_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/dashcam_file.dart';
import '../models/dashcam_state.dart';

/// HTTP API client for Novatek CARDV-based dashcams (e.g. Onelap).
/// All communication is via HTTP GET to 192.168.1.254.
class DashcamService {
  DashcamService._();

  /// Configurable IP — defaults to common Novatek dashcam address.
  static String ip = '192.168.1.254';
  static String get baseUrl => 'http://$ip';

  static const Duration _cmdTimeout = Duration(seconds: 5);
  static const Duration _downloadTimeout = Duration(seconds: 120);

  // ── Low-level command ──────────────────────────────────────────────────

  /// Send a command and return the raw XML response body.
  static Future<String> _sendCommand(int cmd, {int? par, String? str}) async {
    var url = '$baseUrl/?custom=1&cmd=$cmd';
    if (par != null) url += '&par=$par';
    if (str != null) url += '&str=${Uri.encodeComponent(str)}';

    debugPrint('DashcamService CMD → $url');
    final client = HttpClient()..connectionTimeout = _cmdTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(_cmdTimeout);
      final body = await response.transform(utf8.decoder).join();
      debugPrint('DashcamService RSP ← [${response.statusCode}] ${body.length > 500 ? '${body.substring(0, 500)}...' : body}');
      return body;
    } finally {
      client.close(force: true);
    }
  }

  /// Fetch a raw URL and return the response body. For debugging/probing.
  static Future<String> fetchRaw(String url) async {
    debugPrint('DashcamService RAW → $url');
    final client = HttpClient()..connectionTimeout = _cmdTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(_cmdTimeout);
      final body = await response.transform(utf8.decoder).join();
      debugPrint('DashcamService RAW ← [${response.statusCode}] ${body.length > 1000 ? '${body.substring(0, 1000)}...' : body}');
      return body;
    } finally {
      client.close(force: true);
    }
  }

  /// Extract <Status> value from XML response. Returns 0 on success.
  static int _parseStatus(String xml) {
    final m = RegExp(r'<Status>(-?\d+)</Status>').firstMatch(xml);
    return int.tryParse(m?.group(1) ?? '-1') ?? -1;
  }

  // ── Connection ─────────────────────────────────────────────────────────

  /// Check if dashcam is reachable at the current IP. Returns true on success.
  static Future<bool> checkConnection() async {
    try {
      final xml = await _sendCommand(3016);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  /// Try to reach a specific IP with the dashcam heartbeat command.
  static Future<bool> _probeIp(String testIp) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      // Try heartbeat command first
      final url = 'http://$testIp/?custom=1&cmd=3016';
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res.transform(utf8.decoder).join();
      if (body.contains('Status') || res.statusCode == 200) return true;
    } catch (_) {}
    try {
      // Fallback: just see if HTTP server responds at all
      final req = await client.getUrl(Uri.parse('http://$testIp/'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode >= 200 && res.statusCode < 500) return true;
    } catch (_) {}
    client.close(force: true);
    return false;
  }

  /// Auto-discover the dashcam by scanning common IPs and the gateway.
  /// Returns the working IP or null if not found.
  /// [onStatus] is called with progress messages for the UI.
  static Future<String?> autoDiscover({
    void Function(String message)? onStatus,
  }) async {
    // 1. Detect the current gateway IP from network interfaces
    final gatewayIps = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // Derive likely gateway: x.x.x.1 and x.x.x.254
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            gatewayIps.add('${parts[0]}.${parts[1]}.${parts[2]}.1');
            gatewayIps.add('${parts[0]}.${parts[1]}.${parts[2]}.254');
          }
        }
      }
    } catch (_) {}

    // 2. Build candidate list: common dashcam IPs + detected gateways
    final candidates = <String>{
      '192.168.1.254',    // Novatek default
      '192.168.0.1',      // Some models
      '192.168.1.1',      // Some models
      '192.168.42.1',     // Some models
      '192.168.43.1',     // Android hotspot style
      '10.0.0.1',         // Rare
      ...gatewayIps,
    };

    onStatus?.call('Scanning ${candidates.length} addresses...');
    debugPrint('DashcamService: auto-discover candidates: $candidates');

    // 3. Probe all candidates in parallel with short timeout
    final futures = <Future<String?>>[];
    for (final candidate in candidates) {
      futures.add(() async {
        onStatus?.call('Trying $candidate...');
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

  /// Send heartbeat to keep Wi-Fi alive.
  static Future<bool> sendHeartbeat() async {
    try {
      await _sendCommand(3016);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Device info ────────────────────────────────────────────────────────

  static Future<DashcamDeviceInfo> getDeviceInfo() async {
    final xml = await _sendCommand(3012);
    return DashcamDeviceInfo.fromXml(xml);
  }

  static Future<DashcamStorageInfo> getStorageInfo() async {
    final xml = await _sendCommand(3017);
    return DashcamStorageInfo.fromXml(xml);
  }

  // ── File operations ────────────────────────────────────────────────────

  /// List all files on the dashcam. Tries multiple API variants.
  static Future<List<DashcamFile>> listFiles() async {
    // Switch to playback mode first (required by some firmware)
    try { await _sendCommand(3001, par: 2); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));

    // Try cmd=3015 (standard CARDV)
    try {
      final xml = await _sendCommand(3015);
      var files = DashcamFile.parseFileListXml(xml);
      if (files.isNotEmpty) return files;

      // Also try with par=0
      final xml2 = await _sendCommand(3015, par: 0);
      files = DashcamFile.parseFileListXml(xml2);
      if (files.isNotEmpty) return files;
    } catch (e) {
      debugPrint('DashcamService cmd=3015 failed: $e');
    }

    // Try HTTP directory listing at /DCIM
    try {
      final html = await fetchRaw('$baseUrl/DCIM/');
      final files = DashcamFile.parseDirectoryListing(html, '/DCIM/');
      if (files.isNotEmpty) return files;
    } catch (e) {
      debugPrint('DashcamService /DCIM/ listing failed: $e');
    }

    // Try /SD/DCIM/ or /tmp/SD0/DCIM/
    for (final path in ['/SD/DCIM/', '/tmp/SD0/DCIM/', '/sd/DCIM/']) {
      try {
        final html = await fetchRaw('$baseUrl$path');
        final files = DashcamFile.parseDirectoryListing(html, path);
        if (files.isNotEmpty) return files;
      } catch (_) {}
    }

    // Try cmd=3025 (file count) to see if files exist
    try {
      final xml = await _sendCommand(3025);
      debugPrint('DashcamService file count response: $xml');
    } catch (_) {}

    return [];
  }

  /// Delete a file by its path.
  static Future<bool> deleteFile(String path) async {
    try {
      final xml = await _sendCommand(4003, str: path);
      return _parseStatus(xml) == 0;
    } catch (e) {
      debugPrint('DashcamService deleteFile error: $e');
      return false;
    }
  }

  /// Get a thumbnail image as bytes. Returns null on failure.
  static Future<Uint8List?> getThumbnail(String path) async {
    final url = '$baseUrl/?custom=1&cmd=4002&str=${Uri.encodeComponent(path)}';
    final client = HttpClient()..connectionTimeout = _cmdTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(_cmdTimeout);
      if (response.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(response);
      // Verify it looks like image data (JPEG starts with FF D8)
      if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return bytes;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
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

  // ── Camera control ─────────────────────────────────────────────────────

  static Future<bool> startRecording() async {
    try {
      await _sendCommand(3001, par: 0); // video mode
      await Future.delayed(const Duration(milliseconds: 300));
      final xml = await _sendCommand(2001, par: 1);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopRecording() async {
    try {
      final xml = await _sendCommand(2001, par: 0);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> takePhoto() async {
    try {
      await _sendCommand(3001, par: 1); // photo mode
      await Future.delayed(const Duration(milliseconds: 300));
      final xml = await _sendCommand(1001);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setMode(int mode) async {
    try {
      final xml = await _sendCommand(3001, par: mode);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────

  static Future<bool> setSetting(int cmd, int par) async {
    try {
      final xml = await _sendCommand(cmd, par: par);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> formatSDCard() async {
    try {
      final xml = await _sendCommand(3010);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getAllSettings() async {
    return await _sendCommand(3014);
  }

  static Future<bool> setDateTime(DateTime dt) async {
    final str = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
    try {
      final xml = await _sendCommand(3005, str: str);
      return _parseStatus(xml) == 0;
    } catch (_) {
      return false;
    }
  }

  // ── RTSP stream URLs ──────────────────────────────────────────────────

  static String get rtspFrontUrl => 'rtsp://$ip/xxx.mov';
  static List<String> get rtspUrls => [
    'rtsp://$ip/xxx.mov',
    'rtsp://$ip/live',
    'rtsp://$ip/liveRTSP/av1',
    'rtsp://$ip:554/xxx.mov',
    'http://$ip:8192',
  ];
}
