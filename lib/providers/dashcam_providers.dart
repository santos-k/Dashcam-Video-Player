// lib/providers/dashcam_providers.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashcam_file.dart';
import '../models/dashcam_state.dart';
import '../services/dashcam_service.dart';
import '../services/log_service.dart';
import 'app_providers.dart';

class DashcamNotifier extends StateNotifier<DashcamState> {
  DashcamNotifier(this._ref) : super(const DashcamState());

  final Ref _ref;

  Timer? _heartbeat;

  /// Thumbnail cache: dashcam path -> image bytes
  final Map<String, Uint8List> thumbnailCache = {};

  // ── Connection lifecycle ────────────────────────────────────────────────

  /// Update the dashcam IP address.
  void setIp(String ip) {
    DashcamService.ip = ip;
    appLog('Dashcam', 'IP set to $ip');
  }

  Future<void> connect() async {
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

    appLog('Dashcam', 'Connected to ${DashcamService.ip}');

    // ── Connection flow per Swagger docs ──
    // Step 1: Sync clock + timezone
    try {
      final tz = DateTime.now().timeZoneOffset.inHours;
      await Future.wait([
        DashcamService.setDateTime(DateTime.now()),
        DashcamService.setTimezone(tz),
      ]);
    } catch (_) {}

    // Step 2: Fetch config schema + current values
    await refreshSettings();

    // Step 3: Enter active recorder mode
    await DashcamService.enterRecorder();

    // Step 4: Fetch device info, storage, media info in parallel
    DashcamDeviceInfo? info;
    DashcamStorageInfo? storage;
    DashcamMediaInfo? media;
    try {
      final results = await Future.wait([
        DashcamService.getDeviceInfo().catchError((_) =>
            const DashcamDeviceInfo()),
        DashcamService.getStorageInfo().catchError((_) =>
            const DashcamStorageInfo()),
        DashcamService.getMediaInfo().catchError((_) =>
            const DashcamMediaInfo()),
      ]);
      info = results[0] as DashcamDeviceInfo;
      storage = results[1] as DashcamStorageInfo;
      media = results[2] as DashcamMediaInfo;
    } catch (_) {}

    state = state.copyWith(
      status: DashcamConnectionStatus.connected,
      deviceInfo: info,
      storageInfo: storage,
      mediaInfo: media,
      isRecording: state.paramValue('rec') == 1,
    );

    // Step 5: Fetch file list (loop → emr → event → park)
    await refreshFiles();

    // Step 6: Start heartbeat using getrecduration (per Swagger: highest
    // poll-rate endpoint, serves as both recording timer and keep-alive)
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final duration = await DashcamService.getRecDuration();
        if (mounted) {
          state = state.copyWith(recDuration: duration);
        }
      } catch (_) {
        if (state.status == DashcamConnectionStatus.connected) {
          appLog('Dashcam', 'Heartbeat lost');
          state = state.copyWith(
            status: DashcamConnectionStatus.error,
            errorMessage: 'Lost connection to dashcam.',
          );
          _heartbeat?.cancel();
        }
      }
    });
  }

  void disconnect() {
    appLog('Dashcam', 'Disconnecting');
    _heartbeat?.cancel();
    _heartbeat = null;
    thumbnailCache.clear();
    state = const DashcamState();

    // Remove WiFi pairs from the clip list
    _ref.read(videoPairListProvider.notifier).clearDashcamPairs();
  }

  // ── File operations ────────────────────────────────────────────────────

  Future<void> refreshFiles() async {
    if (state.status != DashcamConnectionStatus.connected) return;
    try {
      appLog('Dashcam', 'Fetching file list');
      final files = await DashcamService.listAllFiles();
      files.sort((a, b) {
        // Newest first by createtime
        if (a.createtime != 0 && b.createtime != 0) {
          return b.createtime.compareTo(a.createtime);
        }
        if (a.timestamp != null && b.timestamp != null) {
          return b.timestamp!.compareTo(a.timestamp!);
        }
        return b.name.compareTo(a.name);
      });
      appLog('Dashcam', 'Found ${files.length} files');
      state = state.copyWith(files: files);

      // Push paired files into the main clip list
      _ref.read(videoPairListProvider.notifier).loadFromDashcam(files);
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
        if (mounted) state = state.copyWith(downloadProgress: p);
      },
    );

    if (mounted) state = state.copyWith(clearDownload: true, downloadProgress: 0);
    appLog('Dashcam', 'Download ${ok ? "complete" : "failed"}: ${file.name}');
    return ok;
  }

  /// Delete a file from the dashcam SD card.
  Future<bool> deleteFile(DashcamFile file) async {
    appLog('Dashcam', 'Deleting ${file.name}');
    final ok = await DashcamService.deleteFile(file.path);
    if (ok) {
      state = state.copyWith(
        files: state.files.where((f) => f.path != file.path).toList(),
      );
      // Re-pair and push to clip list
      _ref.read(videoPairListProvider.notifier).loadFromDashcam(state.files);
      await refreshStorage();
    }
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
    await DashcamService.enterRecorder();
    final ok = await DashcamService.startRecording();
    if (ok) state = state.copyWith(isRecording: true);
  }

  Future<void> stopRecording() async {
    final ok = await DashcamService.stopRecording();
    if (ok) state = state.copyWith(isRecording: false);
  }

  Future<void> switchCamera(int camId) async {
    await DashcamService.switchCamera(camId);
    // Refresh device info to get updated curcamid
    try {
      final info = await DashcamService.getDeviceInfo();
      state = state.copyWith(deviceInfo: info);
    } catch (_) {}
  }

  // ── Settings ───────────────────────────────────────────────────────────

  Future<void> refreshSettings() async {
    if (state.status != DashcamConnectionStatus.connected) return;
    try {
      final results = await Future.wait([
        DashcamService.getParamValues(),
        DashcamService.getParamItems(),
      ]);
      state = state.copyWith(
        params: results[0] as List<DashcamParam>,
        paramSchemas: results[1] as List<DashcamParamSchema>,
      );

      // Update isRecording from params
      final recValue = state.paramValue('rec');
      if (recValue != null) {
        state = state.copyWith(isRecording: recValue == 1);
      }
    } catch (e) {
      debugPrint('DashcamNotifier refreshSettings error: $e');
    }
  }

  Future<bool> setParam(String param, int value) async {
    final ok = await DashcamService.setParam(param, value);
    if (ok) {
      // Update local state immediately
      final updated = state.params.map((p) {
        if (p.name == param) return DashcamParam(name: param, value: value);
        return p;
      }).toList();
      state = state.copyWith(params: updated);

      // Track recording state
      if (param == 'rec') {
        state = state.copyWith(isRecording: value == 1);
      }
    }
    return ok;
  }

  Future<void> syncDateTime() async {
    final tz = DateTime.now().timeZoneOffset.inHours;
    await Future.wait([
      DashcamService.setDateTime(DateTime.now()),
      DashcamService.setTimezone(tz),
    ]);
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}

final dashcamProvider =
    StateNotifierProvider<DashcamNotifier, DashcamState>(
  (ref) => DashcamNotifier(ref),
);
