// lib/widgets/dashcam_file_browser.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/dashcam_file.dart';
import '../providers/dashcam_providers.dart';

class DashcamFileBrowser extends ConsumerWidget {
  final List<DashcamFile> files;
  const DashcamFileBrowser({super.key, required this.files});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dcState = ref.watch(dashcamProvider);
    final videoFiles = files.where((f) => f.isVideo).toList();
    final photoFiles = files.where((f) => f.isPhoto).toList();
    final totalSize  = files.fold<int>(0, (s, f) => s + f.size);

    return Column(children: [
      // Toolbar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(children: [
          Text('${files.length} files',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 8),
          _pill('${videoFiles.length} video', const Color(0xFF4FC3F7)),
          const SizedBox(width: 4),
          _pill('${photoFiles.length} photo', Colors.orange),
          const SizedBox(width: 8),
          Text(_fmtSize(totalSize),
              style: const TextStyle(color: Colors.white30, fontSize: 10)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 18),
            onPressed: () => ref.read(dashcamProvider.notifier).refreshFiles(),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ),

      // File list
      Expanded(
        child: files.isEmpty
            ? const Center(child: Text('No files on dashcam',
                style: TextStyle(color: Colors.white30, fontSize: 13)))
            : ListView.builder(
                itemCount: files.length,
                itemBuilder: (_, i) => _FileTile(
                  file: files[i],
                  isDownloading: dcState.activeDownload == files[i].path,
                  downloadProgress: dcState.activeDownload == files[i].path
                      ? dcState.downloadProgress : 0,
                ),
              ),
      ),
    ]);
  }

  static Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      border: Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
  );

  static String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ─── File tile ──────────────────────────────────────────────────────────────

class _FileTile extends ConsumerStatefulWidget {
  final DashcamFile file;
  final bool isDownloading;
  final double downloadProgress;

  const _FileTile({
    required this.file,
    required this.isDownloading,
    required this.downloadProgress,
  });

  @override
  ConsumerState<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends ConsumerState<_FileTile> {
  Uint8List? _thumb;
  bool _thumbLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final bytes = await ref.read(dashcamProvider.notifier)
        .getThumbnail(widget.file.path);
    if (mounted) setState(() { _thumb = bytes; _thumbLoaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final fmt = DateFormat('MMM d, yyyy  HH:mm:ss');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(children: [
        // Thumbnail
        Container(
          width: 72, height: 44,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: _thumbLoaded && _thumb != null
              ? Image.memory(_thumb!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _thumbPlaceholder(file))
              : _thumbPlaceholder(file),
        ),
        const SizedBox(width: 12),

        // Info
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Text(file.displaySize,
                  style: const TextStyle(color: Colors.white30, fontSize: 10)),
              const SizedBox(width: 8),
              if (file.timestamp != null)
                Text(fmt.format(file.timestamp!),
                    style: const TextStyle(color: Colors.white30, fontSize: 10)),
              const SizedBox(width: 6),
              if (file.isFront)
                _typeBadge('Front', const Color(0xFF4FC3F7))
              else if (file.isBack)
                _typeBadge('Back', Colors.orange),
              const SizedBox(width: 4),
              _typeBadge(file.folderLabel,
                  file.folder == 'emr' ? Colors.redAccent
                  : file.folder == 'park' ? Colors.amber
                  : Colors.white38),
            ]),
            // Download progress bar
            if (widget.isDownloading) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: widget.downloadProgress,
                backgroundColor: Colors.white10,
                color: const Color(0xFF4FC3F7),
                minHeight: 3,
              ),
            ],
          ],
        )),

        const SizedBox(width: 8),

        // Actions
        if (!widget.isDownloading) ...[
          // Play (video only)
          if (file.isVideo)
            _ActionIcon(Icons.play_circle_outline_rounded, 'Play',
                const Color(0xFF4FC3F7), () => _playFile(file)),
          // Download
          _ActionIcon(Icons.download_rounded, 'Download',
              Colors.white54, () => _downloadFile(file)),
          // Delete (not available on all dashcam firmwares)
          // _ActionIcon(Icons.delete_outline_rounded, 'Delete',
          //     Colors.redAccent, () => _deleteFile(file)),
        ] else
          const SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7))),
      ]),
    );
  }

  Widget _thumbPlaceholder(DashcamFile file) => Center(
    child: Icon(
      file.isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
      color: Colors.white12, size: 20,
    ),
  );

  Widget _typeBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700)),
  );

  void _playFile(DashcamFile file) {
    // Open the HTTP URL directly in a simple video dialog
    showDialog(
      context: context,
      builder: (_) => _PlayDialog(url: file.downloadUrl, name: file.name),
    );
  }

  Future<void> _downloadFile(DashcamFile file) async {
    final outDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Save dashcam file to',
    );
    if (outDir == null) return;
    final ok = await ref.read(dashcamProvider.notifier)
        .downloadFile(file, outDir);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Downloaded ${file.name}'
            : 'Download failed: ${file.name}'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _ActionIcon(this.icon, this.tooltip, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 18),
      ),
    ),
  );
}

// ─── Video play dialog using media_kit ──────────────────────────────────────

class _PlayDialog extends StatefulWidget {
  final String url;
  final String name;
  const _PlayDialog({required this.url, required this.name});

  @override
  State<_PlayDialog> createState() => _PlayDialogState();
}

class _PlayDialogState extends State<_PlayDialog> {
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _openVideo();
  }

  Future<void> _openVideo() async {
    try {
      await _player.open(Media(widget.url), play: true);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: (screenSize.width * 0.7).clamp(400, 900),
        height: (screenSize.height * 0.7).clamp(300, 600),
        child: Column(children: [
          // Title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(children: [
              const Icon(Icons.play_circle_rounded, color: Color(0xFF4FC3F7), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          // Video area
          Expanded(
            child: _error != null
                ? Center(child: Text('Playback error: $_error',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center))
                : _loading
                    ? const Center(child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF4FC3F7)))
                    : Container(
                        color: Colors.black,
                        child: Video(
                          controller: _controller,
                          fit: BoxFit.contain,
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}
