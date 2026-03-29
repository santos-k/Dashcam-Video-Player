// lib/providers/dashcam_providers.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashcam_file.dart';
import '../models/dashcam_state.dart';
import '../services/dashcam_service.dart';
import '../services/log_service.dart';

class DashcamNotifier extends StateNotifier<DashcamState> {
  DashcamNotifier() : super(const DashcamState());

  Timer? _heartbeat;

  /// Thumbnail cache: dashcam path -> image bytes
  final Map<String, Uint8List> thumbnailCache = {};

  // ── Connection lifecycle ────────────────────────────────────────────────

  /// Update the dashcam IP address.
  void setIp(String ip) {
    DashcamService.ip = ip;
    DashcamFile.setIp(ip);
    appLog('Dashcam', 'IP set to $ip');
  }

  Future<void> connect() async {
    DashcamFile.setIp(DashcamService.ip); // sync
    state = state.copyWith(
        status: DashcamConnectionStatus.connecting, clearError: true);
    appLog('Dashcam', 'Connecting to ${DashcamService.ip}...');

    // First try the configured IP
    var ok = await DashcamService.checkConnection();

    // If that fails, auto-discover
    if (!ok) {
      appLog('Dashcam', 'Direct connection failed, auto-discovering...');
      final foundIp = await DashcamService.autoDiscover(
        onStatus: (msg) => appLog('Dashcam', msg),
      );
      if (foundIp != null) {
        DashcamService.ip = foundIp;
        DashcamFile.setIp(foundIp);
        ok = true;
        appLog('Dashcam', 'Auto-discovered dashcam at $foundIp');
      }
    }

    if (!ok) {
      appLog('Dashcam', 'Connection failed');
      state = state.copyWith(
        status: DashcamConnectionStatus.error,
        errorMessage: 'Cannot find dashcam on this network.\n'
            'Make sure you are connected to the dashcam Wi-Fi\n'
            'and try entering the correct IP manually.',
      );
      return;
    }

    appLog('Dashcam', 'Connected');

    // Fetch device info + storage
    DashcamDeviceInfo? info;
    DashcamStorageInfo? storage;
    try { info    = await DashcamService.getDeviceInfo(); } catch (_) {}
    try { storage = await DashcamService.getStorageInfo(); } catch (_) {}

    state = state.copyWith(
      status:      DashcamConnectionStatus.connected,
      deviceInfo:  info,
      storageInfo: storage,
    );

    // Start heartbeat
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
      final alive = await DashcamService.sendHeartbeat();
      if (!alive && state.status == DashcamConnectionStatus.connected) {
        appLog('Dashcam', 'Heartbeat lost');
        state = state.copyWith(
          status: DashcamConnectionStatus.error,
          errorMessage: 'Lost connection to dashcam.',
        );
        _heartbeat?.cancel();
      }
    });

    // Fetch file list
    await refreshFiles();
  }

  void disconnect() {
    appLog('Dashcam', 'Disconnecting');
    _heartbeat?.cancel();
    _heartbeat = null;
    thumbnailCache.clear();
    state = const DashcamState();
  }

  // ── File operations ────────────────────────────────────────────────────

  Future<void> refreshFiles() async {
    if (state.status != DashcamConnectionStatus.connected) return;
    try {
      appLog('Dashcam', 'Fetching file list');
      final files = await DashcamService.listFiles();
      files.sort((a, b) {
        // Newest first
        if (a.timestamp != null && b.timestamp != null) {
          return b.timestamp!.compareTo(a.timestamp!);
        }
        return b.name.compareTo(a.name);
      });
      appLog('Dashcam', 'Found ${files.length} files');
      state = state.copyWith(files: files);
    } catch (e) {
      debugPrint('DashcamNotifier refreshFiles error: $e');
    }
  }

  Future<void> refreshStorage() async {
    if (state.status != DashcamConnectionStatus.connected) return;
    try {
      final storage = await DashcamService.getStorageInfo();
      state = state.copyWith(storageInfo: storage);
    } catch (_) {}
  }

  Future<bool> deleteFile(DashcamFile file) async {
    appLog('Dashcam', 'Deleting ${file.name}');
    final ok = await DashcamService.deleteFile(file.path);
    if (ok) {
      state = state.copyWith(
        files: state.files.where((f) => f.path != file.path).toList(),
      );
      await refreshStorage();
    }
    return ok;
  }

  Future<bool> downloadFile(DashcamFile file, String localDir) async {
    if (state.activeDownload != null) return false; // one at a time
    final localPath = '$localDir/${file.name}';
    state = state.copyWith(
      activeDownload: file.path,
      downloadProgress: 0,
    );
    appLog('Dashcam', 'Downloading ${file.name} → $localPath');

    final ok = await DashcamService.downloadFile(
      remotePath: file.path,
      localPath: localPath,
      fileSize: file.size,
      onProgress: (p) {
        state = state.copyWith(downloadProgress: p);
      },
    );

    state = state.copyWith(clearDownload: true, downloadProgress: 0);
    appLog('Dashcam', 'Download ${ok ? "complete" : "failed"}: ${file.name}');
    return ok;
  }

  /// Fetch thumbnail bytes (cached).
  Future<Uint8List?> getThumbnail(String path) async {
    if (thumbnailCache.containsKey(path)) return thumbnailCache[path];
    final bytes = await DashcamService.getThumbnail(path);
    if (bytes != null) thumbnailCache[path] = bytes;
    return bytes;
  }

  // ── Camera control ─────────────────────────────────────────────────────

  Future<void> startRecording() async {
    final ok = await DashcamService.startRecording();
    if (ok) state = state.copyWith(isRecording: true);
  }

  Future<void> stopRecording() async {
    final ok = await DashcamService.stopRecording();
    if (ok) state = state.copyWith(isRecording: false);
  }

  Future<void> takePhoto() async {
    await DashcamService.takePhoto();
  }

  // ── Settings ───────────────────────────────────────────────────────────

  Future<bool> formatSD() async {
    appLog('Dashcam', 'Formatting SD card');
    final ok = await DashcamService.formatSDCard();
    if (ok) {
      state = state.copyWith(files: []);
      await refreshStorage();
    }
    return ok;
  }

  Future<void> syncDateTime() async {
    await DashcamService.setDateTime(DateTime.now());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}

final dashcamProvider =
    StateNotifierProvider<DashcamNotifier, DashcamState>(
  (ref) => DashcamNotifier(),
);
