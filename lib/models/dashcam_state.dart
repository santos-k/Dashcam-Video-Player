// lib/models/dashcam_state.dart

import 'dashcam_file.dart';

enum DashcamConnectionStatus { disconnected, connecting, connected, error }

class DashcamDeviceInfo {
  final String model;
  final String firmware;
  const DashcamDeviceInfo({this.model = 'Unknown', this.firmware = ''});

  factory DashcamDeviceInfo.fromXml(String xml) {
    final model = _tag(xml, 'Model') ?? _tag(xml, 'model') ?? 'Dashcam';
    final fw = _tag(xml, 'FW') ?? _tag(xml, 'SoftwareVersion') ?? _tag(xml, 'fw') ?? '';
    return DashcamDeviceInfo(model: model, firmware: fw);
  }

  static String? _tag(String xml, String name) {
    final m = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    return m?.group(1)?.trim();
  }
}

class DashcamStorageInfo {
  final int totalKB;
  final int freeKB;
  const DashcamStorageInfo({this.totalKB = 0, this.freeKB = 0});

  int get usedKB => totalKB - freeKB;
  double get usedPercent => totalKB > 0 ? usedKB / totalKB : 0;

  String get totalDisplay => _fmt(totalKB);
  String get freeDisplay  => _fmt(freeKB);
  String get usedDisplay  => _fmt(usedKB);

  static String _fmt(int kb) {
    if (kb < 1024) return '$kb KB';
    if (kb < 1024 * 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
    return '${(kb / (1024 * 1024)).toStringAsFixed(1)} GB';
  }

  factory DashcamStorageInfo.fromXml(String xml) {
    final total = int.tryParse(
        RegExp(r'<TotalSpace>(\d+)</TotalSpace>').firstMatch(xml)?.group(1) ?? '0') ?? 0;
    final free = int.tryParse(
        RegExp(r'<FreeSpace>(\d+)</FreeSpace>').firstMatch(xml)?.group(1) ?? '0') ?? 0;
    return DashcamStorageInfo(totalKB: total, freeKB: free);
  }
}

class DashcamState {
  final DashcamConnectionStatus status;
  final String? errorMessage;
  final DashcamDeviceInfo? deviceInfo;
  final DashcamStorageInfo? storageInfo;
  final List<DashcamFile> files;
  final String? activeDownload;     // path being downloaded, null if idle
  final double downloadProgress;    // 0.0 - 1.0
  final bool isRecording;

  const DashcamState({
    this.status = DashcamConnectionStatus.disconnected,
    this.errorMessage,
    this.deviceInfo,
    this.storageInfo,
    this.files = const [],
    this.activeDownload,
    this.downloadProgress = 0,
    this.isRecording = false,
  });

  DashcamState copyWith({
    DashcamConnectionStatus? status,
    String? errorMessage,
    DashcamDeviceInfo? deviceInfo,
    DashcamStorageInfo? storageInfo,
    List<DashcamFile>? files,
    String? activeDownload,
    double? downloadProgress,
    bool? isRecording,
    bool clearError = false,
    bool clearDownload = false,
  }) =>
      DashcamState(
        status:           status           ?? this.status,
        errorMessage:     clearError ? null : (errorMessage ?? this.errorMessage),
        deviceInfo:       deviceInfo       ?? this.deviceInfo,
        storageInfo:      storageInfo      ?? this.storageInfo,
        files:            files            ?? this.files,
        activeDownload:   clearDownload ? null : (activeDownload ?? this.activeDownload),
        downloadProgress: downloadProgress ?? this.downloadProgress,
        isRecording:      isRecording      ?? this.isRecording,
      );
}
