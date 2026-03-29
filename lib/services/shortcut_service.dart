// lib/services/shortcut_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/shortcut_action.dart';

/// Persists keyboard shortcut bindings to a JSON file next to the executable.
class ShortcutService {
  ShortcutService._();

  static late final String _filePath;

  /// Call once at app startup, before reading config.
  static void init() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _filePath = p.join(exeDir, 'shortcuts.json');
  }

  /// Load saved config, falling back to defaults if missing or corrupt.
  static ShortcutConfig load() {
    try {
      final file = File(_filePath);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return ShortcutConfig.fromJson(json);
      }
    } catch (e) {
      debugPrint('ShortcutService: failed to load shortcuts.json: $e');
    }
    return ShortcutConfig.defaults();
  }

  /// Save config to disk.
  static Future<void> save(ShortcutConfig config) async {
    try {
      final file = File(_filePath);
      final json = const JsonEncoder.withIndent('  ').convert(config.toJson());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('ShortcutService: failed to save shortcuts.json: $e');
    }
  }
}
