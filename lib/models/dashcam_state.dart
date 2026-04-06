// lib/models/dashcam_state.dart

import 'dashcam_file.dart';

enum DashcamConnectionStatus { disconnected, connecting, connected, error }

/// Device attributes from GET /app/getdeviceattr
class DashcamDeviceInfo {
  final String uuid;
  final String ssid;
  final String bssid;
  final String softver;
  final String hwver;
  final String otaver;
  final int camnum;
  final int curcamid;

  const DashcamDeviceInfo({
    this.uuid = '',
    this.ssid = '',
    this.bssid = '',
    this.softver = '',
    this.hwver = '',
    this.otaver = '',
    this.camnum = 1,
    this.curcamid = 0,
  });

  /// Human-readable model/firmware for display.
  String get model => ssid.isNotEmpty ? ssid : 'Dashcam';
  String get firmware => softver;

  factory DashcamDeviceInfo.fromJson(Map<String, dynamic> json) {
    return DashcamDeviceInfo(
      uuid: json['uuid'] as String? ?? '',
      ssid: json['ssid'] as String? ?? '',
      bssid: json['bssid'] as String? ?? '',
      softver: json['softver'] as String? ?? '',
      hwver: json['hwver'] as String? ?? '',
      otaver: json['otaver'] as String? ?? '',
      camnum: json['camnum'] as int? ?? 1,
      curcamid: json['curcamid'] as int? ?? 0,
    );
  }
}

/// SD card info from GET /app/getsdinfo
class DashcamStorageInfo {
  final int status; // 0 = OK
  final int freeMB;
  final int totalMB;

  const DashcamStorageInfo({this.status = 0, this.freeMB = 0, this.totalMB = 0});

  int get usedMB => totalMB - freeMB;
  double get usedPercent => totalMB > 0 ? usedMB / totalMB : 0;

  String get totalDisplay => _fmt(totalMB);
  String get freeDisplay => _fmt(freeMB);
  String get usedDisplay => _fmt(usedMB);

  static String _fmt(int mb) {
    if (mb < 1024) return '$mb MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  factory DashcamStorageInfo.fromJson(Map<String, dynamic> json) {
    return DashcamStorageInfo(
      status: json['status'] as int? ?? -1,
      freeMB: json['free'] as int? ?? 0,
      totalMB: json['total'] as int? ?? 0,
    );
  }
}

/// RTSP media info from GET /app/getmediainfo
class DashcamMediaInfo {
  final String rtsp;
  final String transport;
  final int port;

  const DashcamMediaInfo({
    this.rtsp = '',
    this.transport = 'tcp',
    this.port = 5000,
  });

  factory DashcamMediaInfo.fromJson(Map<String, dynamic> json) {
    return DashcamMediaInfo(
      rtsp: json['rtsp'] as String? ?? '',
      transport: json['transport'] as String? ?? 'tcp',
      port: json['port'] as int? ?? 5000,
    );
  }
}

/// A single param current value from getparamvalue.
class DashcamParam {
  final String name;
  final int value;

  const DashcamParam({required this.name, required this.value});

  factory DashcamParam.fromJson(Map<String, dynamic> json) {
    return DashcamParam(
      name: json['name'] as String? ?? '',
      value: json['value'] as int? ?? 0,
    );
  }
}

/// Schema for a param from getparamitems — available options.
class DashcamParamSchema {
  final String name;
  final List<String> items; // labels: ["off","on"], ["2K","4K"]
  final List<int> index; // indices:  [0,1],         [3,5]

  const DashcamParamSchema({
    required this.name,
    this.items = const [],
    this.index = const [],
  });

  factory DashcamParamSchema.fromJson(Map<String, dynamic> json) {
    return DashcamParamSchema(
      name: json['name'] as String? ?? '',
      items: (json['items'] as List?)?.cast<String>() ?? [],
      index: (json['index'] as List?)?.cast<int>() ?? [],
    );
  }

  /// Get the label for a given value index, or null.
  String? labelForValue(int value) {
    final i = index.indexOf(value);
    return i >= 0 && i < items.length ? items[i] : null;
  }
}

/// Full dashcam connection state.
class DashcamState {
  final DashcamConnectionStatus status;
  final String? errorMessage;
  final DashcamDeviceInfo? deviceInfo;
  final DashcamStorageInfo? storageInfo;
  final DashcamMediaInfo? mediaInfo;
  final List<DashcamFile> files;
  final String? activeDownload; // path being downloaded, null if idle
  final double downloadProgress; // 0.0 - 1.0
  final bool isRecording;
  final int recDuration; // current recording duration in seconds
  final List<DashcamParam> params; // current settings values
  final List<DashcamParamSchema> paramSchemas; // settings schema

  const DashcamState({
    this.status = DashcamConnectionStatus.disconnected,
    this.errorMessage,
    this.deviceInfo,
    this.storageInfo,
    this.mediaInfo,
    this.files = const [],
    this.activeDownload,
    this.downloadProgress = 0,
    this.isRecording = false,
    this.recDuration = 0,
    this.params = const [],
    this.paramSchemas = const [],
  });

  /// Get current value for a param name, or null.
  int? paramValue(String name) {
    for (final p in params) {
      if (p.name == name) return p.value;
    }
    return null;
  }

  /// Get schema for a param name, or null.
  DashcamParamSchema? paramSchema(String name) {
    for (final s in paramSchemas) {
      if (s.name == name) return s;
    }
    return null;
  }

  DashcamState copyWith({
    DashcamConnectionStatus? status,
    String? errorMessage,
    DashcamDeviceInfo? deviceInfo,
    DashcamStorageInfo? storageInfo,
    DashcamMediaInfo? mediaInfo,
    List<DashcamFile>? files,
    String? activeDownload,
    double? downloadProgress,
    bool? isRecording,
    int? recDuration,
    List<DashcamParam>? params,
    List<DashcamParamSchema>? paramSchemas,
    bool clearError = false,
    bool clearDownload = false,
  }) =>
      DashcamState(
        status: status ?? this.status,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
        deviceInfo: deviceInfo ?? this.deviceInfo,
        storageInfo: storageInfo ?? this.storageInfo,
        mediaInfo: mediaInfo ?? this.mediaInfo,
        files: files ?? this.files,
        activeDownload:
            clearDownload ? null : (activeDownload ?? this.activeDownload),
        downloadProgress: downloadProgress ?? this.downloadProgress,
        isRecording: isRecording ?? this.isRecording,
        recDuration: recDuration ?? this.recDuration,
        params: params ?? this.params,
        paramSchemas: paramSchemas ?? this.paramSchemas,
      );
}
