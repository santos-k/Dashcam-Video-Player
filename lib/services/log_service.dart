// lib/services/log_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

/// Simple file-based logger that writes every user/system action to a daily
/// log file inside a `logs/` directory next to the executable (or in the
/// project root during development).
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  IOSink? _sink;
  String? _currentDay;
  late final Directory _logDir;

  /// Call once at app startup.
  Future<void> init() async {
    // Resolve log directory: next to the executable in release, or
    // project-root/logs during development.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _logDir = Directory(p.join(exeDir, 'logs'));
    if (!_logDir.existsSync()) {
      _logDir.createSync(recursive: true);
    }
    _openForToday();
    log('App', 'Logger initialised – log dir: ${_logDir.path}');
  }

  void _openForToday() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (today == _currentDay && _sink != null) return;
    _sink?.flush();
    _sink?.close();
    _currentDay = today;
    final file = File(p.join(_logDir.path, 'dashcam_$today.log'));
    _sink = file.openWrite(mode: FileMode.append);
  }

  /// Write a timestamped log line.
  ///
  /// [category] groups related actions (e.g. "Playback", "Folder", "UI").
  /// [message] is a human-readable description of the action.
  void log(String category, String message) {
    _openForToday(); // roll over at midnight
    final ts = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final line = '[$ts] [$category] $message';
    _sink?.writeln(line);
    debugPrint(line);
  }

  /// Flush and close the current log file (call on app shutdown).
  Future<void> dispose() async {
    log('App', 'Logger shutting down');
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

/// Convenience top-level accessor so callers don't need to type
/// `LogService.instance.log(...)` everywhere.
void appLog(String category, String message) =>
    LogService.instance.log(category, message);
