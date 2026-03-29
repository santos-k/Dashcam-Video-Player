// lib/services/dashcam_tcp_service.dart
//
// Raw TCP JSON protocol client for Onelap dashcam (port 5000).
// Messages are newline-delimited JSON with "msgid" field.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Manages a persistent TCP connection to the dashcam on port 5000.
class DashcamTcpService {
  DashcamTcpService._();

  static Socket? _socket;
  static StreamSubscription? _sub;
  static final _responseCtrl = StreamController<Map<String, dynamic>>.broadcast();
  static String _buffer = '';

  /// Stream of all incoming JSON messages from the dashcam.
  static Stream<Map<String, dynamic>> get messages => _responseCtrl.stream;

  /// Whether the TCP connection is active.
  static bool get isConnected => _socket != null;

  /// Connect to the dashcam TCP port.
  static Future<bool> connect(String ip, {int port = 5000}) async {
    await disconnect();
    try {
      _socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 5));
      debugPrint('DashcamTCP: connected to $ip:$port');

      _buffer = '';
      _sub = _socket!.listen(
        (data) {
          _buffer += String.fromCharCodes(data);
          // Parse newline-delimited JSON or brace-delimited
          _parseBuffer();
        },
        onError: (e) {
          debugPrint('DashcamTCP: socket error: $e');
          disconnect();
        },
        onDone: () {
          debugPrint('DashcamTCP: socket closed by remote');
          disconnect();
        },
      );
      return true;
    } catch (e) {
      debugPrint('DashcamTCP: connect failed: $e');
      return false;
    }
  }

  static void _parseBuffer() {
    // Try to extract complete JSON objects from the buffer.
    // Messages may be newline-delimited or concatenated.
    while (_buffer.isNotEmpty) {
      final start = _buffer.indexOf('{');
      if (start < 0) {
        _buffer = '';
        return;
      }
      if (start > 0) _buffer = _buffer.substring(start);

      // Find matching closing brace
      int depth = 0;
      int end = -1;
      for (int i = 0; i < _buffer.length; i++) {
        if (_buffer[i] == '{') depth++;
        if (_buffer[i] == '}') depth--;
        if (depth == 0) { end = i; break; }
      }
      if (end < 0) return; // incomplete, wait for more data

      final jsonStr = _buffer.substring(0, end + 1);
      _buffer = _buffer.substring(end + 1);

      try {
        final msg = jsonDecode(jsonStr) as Map<String, dynamic>;
        debugPrint('DashcamTCP ← ${msg['msgid'] ?? 'unknown'}: ${jsonStr.length > 300 ? '${jsonStr.substring(0, 300)}...' : jsonStr}');
        _responseCtrl.add(msg);
      } catch (e) {
        debugPrint('DashcamTCP: parse error: $e for: ${jsonStr.substring(0, jsonStr.length.clamp(0, 100))}');
      }
    }
  }

  /// Send a JSON command and optionally wait for a response with matching msgid.
  static Future<Map<String, dynamic>?> send(
    String msgid, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 5),
    bool waitResponse = true,
  }) async {
    if (_socket == null) return null;

    final msg = <String, dynamic>{'msgid': msgid};
    if (params != null) msg.addAll(params);

    final json = jsonEncode(msg);
    debugPrint('DashcamTCP → $json');

    try {
      _socket!.write(json);
      await _socket!.flush();
    } catch (e) {
      debugPrint('DashcamTCP: send error: $e');
      return null;
    }

    if (!waitResponse) return {};

    // Wait for a response with matching msgid
    try {
      final resp = await _responseCtrl.stream
          .where((m) => m['msgid'] == msgid)
          .first
          .timeout(timeout);
      return resp;
    } catch (_) {
      return null;
    }
  }

  /// Send a raw string and collect ALL raw data for a duration.
  /// Returns both parsed JSON messages and raw non-JSON bytes.
  static Future<(List<Map<String, dynamic>>, String)> sendAndCollect(
    String rawJson, {
    Duration collectDuration = const Duration(seconds: 2),
  }) async {
    if (_socket == null) return (<Map<String, dynamic>>[], '');

    final collected = <Map<String, dynamic>>[];
    final sub = _responseCtrl.stream.listen((m) => collected.add(m));

    try {
      // Send with newline terminator (common in line-based protocols)
      _socket!.write('$rawJson\n');
      await _socket!.flush();
    } catch (_) {}

    await Future.delayed(collectDuration);
    await sub.cancel();
    return (collected, '');
  }

  /// Probe the dashcam with many known msgid values and return results.
  static Future<Map<String, String>> probeCommands() async {
    final results = <String, String>{};

    // Common dashcam TCP JSON commands
    final commands = [
      // File operations
      'get_file_list', 'file_list', 'list_files', 'filelist',
      'get_thumb', 'get_thumbnail',
      // Camera info
      'get_camera_info', 'camera_info', 'get_device_info', 'device_info',
      'get_status', 'status', 'get_info', 'info',
      'get_version', 'version', 'get_fw_version',
      // Storage
      'get_storage', 'storage_info', 'get_sd_info', 'get_disk_info',
      'get_battery', 'battery_info',
      // Settings
      'get_setting', 'get_settings', 'get_config',
      'get_all_settings', 'get_camera_setting',
      // Recording
      'get_record_state', 'record_state', 'get_rec_status',
      'start_record', 'stop_record',
      // Stream
      'get_stream', 'start_stream', 'start_preview',
      'get_live_url', 'get_rtsp_url', 'get_stream_url',
      // GPS
      'gps', 'get_gps',
      // Misc
      'heartbeat', 'keep_alive', 'ping',
      'get_wifi_info', 'wifi_info',
      'get_capability', 'capability',
    ];

    for (final cmd in commands) {
      try {
        final resp = await send(cmd, timeout: const Duration(seconds: 2));
        if (resp != null) {
          final str = jsonEncode(resp);
          results[cmd] = str.length > 200 ? '${str.substring(0, 200)}...' : str;
        } else {
          results[cmd] = '(no response)';
        }
      } catch (_) {
        results[cmd] = '(error)';
      }
    }

    return results;
  }

  static Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    _buffer = '';
  }
}
