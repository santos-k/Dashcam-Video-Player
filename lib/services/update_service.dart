// lib/services/update_service.dart

import 'dart:convert';
import 'dart:io';
import 'log_service.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final String? htmlUrl;
  final bool hasUpdate;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.htmlUrl,
    required this.hasUpdate,
  });
}

class UpdateService {
  static const _repo = 'santos-k/Dashcam-Video-Player';
  static const _currentVersion = '3.1.0';

  /// Check for updates via GitHub Releases API first, then fall back to
  /// reading pubspec.yaml from the main branch.
  static Future<UpdateInfo> checkForUpdate() async {
    try {
      // Try GitHub Releases API first
      final result = await _checkGitHubRelease();
      if (result != null) return result;

      // Fall back to raw pubspec.yaml on main branch
      return await _checkPubspecOnMain();
    } catch (e) {
      appLog('Update', 'Check failed: $e');
      rethrow;
    }
  }

  static Future<UpdateInfo?> _checkGitHubRelease() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
      );
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'DashcamPlayer/$_currentVersion');

      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final tagName = (json['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
        if (tagName.isEmpty) return null;

        // Find .exe installer asset
        String? downloadUrl;
        final assets = json['assets'] as List<dynamic>? ?? [];
        for (final asset in assets) {
          final name = (asset['name'] as String?) ?? '';
          if (name.endsWith('.exe') || name.endsWith('.zip') || name.endsWith('.msi')) {
            downloadUrl = asset['browser_download_url'] as String?;
            break;
          }
        }

        final hasUpdate = _isNewer(tagName, _currentVersion);
        appLog('Update', 'Release check: latest=$tagName current=$_currentVersion update=$hasUpdate');

        return UpdateInfo(
          latestVersion: tagName,
          currentVersion: _currentVersion,
          downloadUrl: downloadUrl,
          releaseNotes: json['body'] as String?,
          htmlUrl: json['html_url'] as String?,
          hasUpdate: hasUpdate,
        );
      }

      // 404 = no releases yet
      if (response.statusCode == 404) return null;

      appLog('Update', 'GitHub API returned ${response.statusCode}');
      return null;
    } catch (e) {
      appLog('Update', 'Release API failed: $e');
      return null;
    }
  }

  static Future<UpdateInfo> _checkPubspecOnMain() async {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('https://raw.githubusercontent.com/$_repo/main/pubspec.yaml'),
    );
    request.headers.set('User-Agent', 'DashcamPlayer/$_currentVersion');

    final response = await request.close().timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch pubspec (${response.statusCode})');
    }

    final body = await response.transform(utf8.decoder).join();

    // Parse version from pubspec.yaml (simple regex, no yaml dependency needed)
    final versionMatch = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(body);
    if (versionMatch == null) {
      throw Exception('Could not parse version from remote pubspec');
    }

    final remoteVersion = versionMatch.group(1)!.split('+').first;
    final hasUpdate = _isNewer(remoteVersion, _currentVersion);

    appLog('Update', 'Pubspec check: remote=$remoteVersion current=$_currentVersion update=$hasUpdate');

    return UpdateInfo(
      latestVersion: remoteVersion,
      currentVersion: _currentVersion,
      downloadUrl: 'https://github.com/$_repo/releases',
      htmlUrl: 'https://github.com/$_repo/releases',
      hasUpdate: hasUpdate,
    );
  }

  /// Returns true if [remote] is strictly newer than [current].
  static bool _isNewer(String remote, String current) {
    final rParts = remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final cParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad to same length
    while (rParts.length < 3) { rParts.add(0); }
    while (cParts.length < 3) { cParts.add(0); }

    for (var i = 0; i < 3; i++) {
      if (rParts[i] > cParts[i]) return true;
      if (rParts[i] < cParts[i]) return false;
    }
    return false;
  }
}
