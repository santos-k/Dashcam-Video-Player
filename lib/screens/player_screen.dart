// lib/screens/player_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/app_providers.dart';
import '../models/layout_config.dart';
import '../services/export_service.dart';
import '../widgets/dual_video_view.dart';
import '../widgets/playback_controls.dart';
import '../widgets/layout_selector.dart';
import '../widgets/clip_list_drawer.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _overlayVisible = true;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select dashcam drive or folder (e.g. F:\\)',
    );
    if (result == null) return;

    final dir = Directory(result);

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Scanning for dashcam videos...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    await ref.read(videoPairListProvider.notifier).loadFromRoot(dir);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No dashcam videos found in $result\n'
              'Expected folders: video_front, video_back, video_front_lock, video_back_lock',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    final paired   = pairs.where((p) => p.isPaired).length;
    final frontOnly = pairs.where((p) => p.hasFront && !p.hasBack).length;
    final backOnly  = pairs.where((p) => p.hasBack  && !p.hasFront).length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Found ${pairs.length} clips  '
            '($paired paired, $frontOnly front-only, $backOnly back-only)',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    ref.read(currentIndexProvider.notifier).state = 0;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    await ref.read(playbackProvider.notifier).loadPair(pairs.first, 0);
  }

  Future<void> _export() async {
    final pair = ref.read(currentPairProvider);
    if (pair == null) return;

    final layout     = ref.read(layoutConfigProvider);
    final syncOffset = ref.read(syncOffsetProvider);

    ref.read(exportProgressProvider.notifier).state = 0.0;

    final outPath = await ExportService.exportPair(
      pair:         pair,
      layout:       layout,
      syncOffsetMs: syncOffset,
      onProgress:   (p) =>
          ref.read(exportProgressProvider.notifier).state = p,
    );

    ref.read(exportProgressProvider.notifier).state = null;

    if (outPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed.')),
        );
      }
      return;
    }

    if (mounted) {
      await Share.shareXFiles([XFile(outPath)], text: 'Dashcam export');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairs          = ref.watch(videoPairListProvider);
    final exportProgress = ref.watch(exportProgressProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClipListDrawer(),
      body: GestureDetector(
        onTap: () => setState(() => _overlayVisible = !_overlayVisible),
        child: Column(
          children: [
            AnimatedSlide(
              offset:   _overlayVisible ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 200),
              child: _TopBar(
                clipCount: pairs.length,
                onFolder:  _pickFolder,
                onLayout:  () => showLayoutSelector(context),
                onExport:  pairs.isNotEmpty ? _export : null,
              ),
            ),

            Expanded(
              child: Stack(
                children: [
                  const DualVideoView(),

                  if (exportProgress != null)
                    _ExportOverlay(progress: exportProgress),

                  if (pairs.isEmpty)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_outlined,
                              color: Colors.white24, size: 72),
                          const SizedBox(height: 16),
                          const Text(
                            'Select your dashcam SD card or folder',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'e.g. F:\\  (containing video_front & video_back folders)',
                            style: TextStyle(color: Colors.white24, fontSize: 13),
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton.icon(
                            onPressed: _pickFolder,
                            icon:  const Icon(Icons.folder_open_rounded),
                            label: const Text('Open Drive / Folder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4FC3F7),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            AnimatedSlide(
              offset:   _overlayVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 200),
              child: const PlaybackControls(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int clipCount;
  final VoidCallback onFolder;
  final VoidCallback onLayout;
  final VoidCallback? onExport;

  const _TopBar({
    required this.clipCount,
    required this.onFolder,
    required this.onLayout,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC000000),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 4, right: 4, bottom: 4,
      ),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon:    const Icon(Icons.menu_rounded, color: Colors.white70),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              tooltip: 'Clip list',
            ),
          ),
          const Text(
            'DashCam Player',
            style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
            ),
          ),
          if (clipCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color:        const Color(0xFF4FC3F7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$clipCount clips',
                  style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            icon:    const Icon(Icons.view_quilt_rounded, color: Colors.white70),
            onPressed: onLayout,
            tooltip: 'Layout',
          ),
          IconButton(
            icon:    const Icon(Icons.folder_open_rounded, color: Colors.white70),
            onPressed: onFolder,
            tooltip: 'Open drive/folder',
          ),
          IconButton(
            icon: Icon(
              Icons.ios_share_rounded,
              color: onExport != null ? Colors.white70 : Colors.white24,
            ),
            onPressed: onExport,
            tooltip: 'Export',
          ),
        ],
      ),
    );
  }
}

class _ExportOverlay extends StatelessWidget {
  final double progress;
  const _ExportOverlay({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value:           progress,
                backgroundColor: Colors.white12,
                color:           const Color(0xFF4FC3F7),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Exporting… ${(progress * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}