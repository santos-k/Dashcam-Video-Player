// lib/models/dashcam_file.dart

/// Represents a single file on the dashcam, parsed from cmd=3015 XML response.
class DashcamFile {
  final String path;       // full path e.g. /tmp/SD0/DCIM/100MEDIA/FILE0001.MOV
  final String name;       // filename only
  final int size;          // bytes
  final String timeRaw;    // raw time string from dashcam
  final DateTime? timestamp;

  const DashcamFile({
    required this.path,
    required this.name,
    required this.size,
    required this.timeRaw,
    this.timestamp,
  });

  // Uses DashcamService.baseUrl for dynamic IP
  String get downloadUrl => 'http://${_ip()}$path';
  String get thumbnailUrl => 'http://${_ip()}/?custom=1&cmd=4002&str=$path';
  String get deleteUrl => 'http://${_ip()}/?custom=1&cmd=4003&str=$path';

  // Lazy import to avoid circular dependency
  static String _ip() {
    // Default; overridden at runtime by DashcamService.ip
    return _ipOverride ?? '192.168.1.254';
  }
  static String? _ipOverride;
  static void setIp(String ip) => _ipOverride = ip;

  bool get isVideo {
    final lower = name.toLowerCase();
    return lower.endsWith('.mov') || lower.endsWith('.mp4') ||
           lower.endsWith('.avi') || lower.endsWith('.ts');
  }

  bool get isPhoto {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png');
  }

  String get displaySize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Parse the file list XML from cmd=3015 into a list of DashcamFile objects.
  static List<DashcamFile> parseFileListXml(String xml) {
    final files = <DashcamFile>[];
    final fileBlocks = RegExp(r'<File>(.*?)</File>', dotAll: true)
        .allMatches(xml);

    for (final match in fileBlocks) {
      final block = match.group(1) ?? '';
      final path = _extractTag(block, 'FPATH') ?? _extractTag(block, 'NAME');
      final name = _extractTag(block, 'NAME');
      final sizeStr = _extractTag(block, 'SIZE');
      final timeStr = _extractTag(block, 'TIME') ?? '';

      if (path == null || name == null) continue;

      // Extract just the filename from the full path
      final fileName = name.contains('\\')
          ? name.split('\\').last
          : name.contains('/')
              ? name.split('/').last
              : name;

      // Normalize path: convert A:\DCIM\... to /DCIM/...
      var normalPath = path
          .replaceAll('\\', '/')
          .replaceAll(RegExp(r'^[A-Za-z]:'), '');
      // Ensure leading slash
      if (!normalPath.startsWith('/')) normalPath = '/$normalPath';

      files.add(DashcamFile(
        path: normalPath,
        name: fileName,
        size: int.tryParse(sizeStr ?? '0') ?? 0,
        timeRaw: timeStr,
        timestamp: _parseTime(timeStr),
      ));
    }

    return files;
  }

  static String? _extractTag(String xml, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static DateTime? _parseTime(String time) {
    if (time.isEmpty) return null;
    try {
      // Common formats: "2024/03/15 14:30:22" or "2024-03-15 14:30:22"
      final normalized = time.replaceAll('/', '-');
      return DateTime.tryParse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// Parse an HTTP directory listing (HTML with <a href> links) into files.
  static List<DashcamFile> parseDirectoryListing(String html, String basePath) {
    final files = <DashcamFile>[];

    // Match href links to media files
    final links = RegExp(r'href="([^"]*\.(MOV|MP4|AVI|JPG|JPEG|TS|mov|mp4|avi|jpg|jpeg|ts))"',
        caseSensitive: false)
        .allMatches(html);

    for (final m in links) {
      final href = m.group(1) ?? '';
      if (href.isEmpty) continue;

      final fileName = href.contains('/')
          ? href.split('/').last
          : href;
      final fullPath = href.startsWith('/')
          ? href
          : '$basePath$href';

      files.add(DashcamFile(
        path: fullPath,
        name: fileName,
        size: 0,
        timeRaw: '',
        timestamp: _parseTimestampFromFilename(fileName),
      ));
    }

    return files;
  }

  static DateTime? _parseTimestampFromFilename(String name) {
    // Try to extract YYYYMMDD_HHMMSS or similar from filename
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})[\-_]?(\d{2})(\d{2})(\d{2})')
        .firstMatch(name);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!),
        int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'DashcamFile($name, $displaySize)';
}
