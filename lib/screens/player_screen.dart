// lib/screens/player_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/app_providers.dart';
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
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final playback = ref.read(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final key      = event.logicalKey;
    final shift    = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.space && playback.isLoaded) {
      notifier.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowRight && playback.isLoaded) {
      notifier.seekRelative(const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.arrowLeft && playback.isLoaded) {
      notifier.seekRelative(const Duration(seconds: -10));
    } else if (key == LogicalKeyboardKey.period && shift) {
      _goTo(ref.read(currentIndexProvider) + 1, autoPlay: true);
    } else if (key == LogicalKeyboardKey.comma && shift) {
      _goTo(ref.read(currentIndexProvider) - 1, autoPlay: true);
    }
  }

  void _goTo(int index, {bool autoPlay = true}) {
    final pairs = ref.read(videoPairListProvider);
    if (index < 0 || index >= pairs.length) return;
    ref.read(currentIndexProvider.notifier).state = index;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    ref.read(playbackProvider.notifier).loadPair(pairs[index], 0, autoPlay: autoPlay);
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select dashcam drive or folder',
    );
    if (result == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Scanning for dashcam videos...'),
        ]),
        duration: Duration(seconds: 30),
      ));
    }

    await ref.read(videoPairListProvider.notifier).loadFromRoot(Directory(result));
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No dashcam videos found in $result'),
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }

    final paired    = pairs.where((p) => p.isPaired).length;
    final frontOnly = pairs.where((p) => p.hasFront && !p.hasBack).length;
    final backOnly  = pairs.where((p) => p.hasBack  && !p.hasFront).length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${pairs.length} clips  ($paired paired · $frontOnly front-only · $backOnly back-only)'),
        duration: const Duration(seconds: 3),
      ));
    }

    ref.read(currentIndexProvider.notifier).state = 0;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    await ref.read(playbackProvider.notifier).loadPair(pairs.first, 0, autoPlay: false);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final pairs = ref.watch(videoPairListProvider);

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        drawer: ClipListDrawer(onSelect: (i) => _goTo(i, autoPlay: true)),
        body: GestureDetector(
          onTap: () {
            _focusNode.requestFocus();
            setState(() => _overlayVisible = !_overlayVisible);
          },
          child: Column(children: [
            // Minimal top bar — just title + hamburger
            _MinimalTopBar(clipCount: pairs.length),

            // Video area
            Expanded(
              child: Stack(children: [
                const DualVideoView(),
                if (pairs.isEmpty) _EmptyState(onOpen: _pickFolder),
              ]),
            ),

            // Full controls bar (bottom)
            AnimatedSlide(
              offset:   _overlayVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 200),
              child: PlaybackControls(
                onPrevious: () => _goTo(ref.read(currentIndexProvider) - 1, autoPlay: true),
                onNext:     () => _goTo(ref.read(currentIndexProvider) + 1, autoPlay: true),
                onFolder:   _pickFolder,
                onLayout:   () => showLayoutSelector(context),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Minimal top bar ──────────────────────────────────────────────────────────

class _MinimalTopBar extends StatelessWidget {
  final int clipCount;
  const _MinimalTopBar({required this.clipCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC000000),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 2,
        left: 4, right: 12, bottom: 2,
      ),
      child: Row(children: [
        Builder(
          builder: (ctx) => IconButton(
            icon:    const Icon(Icons.menu_rounded, color: Colors.white60),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Clip list',
            iconSize: 20,
          ),
        ),
        const Text('DashCam Player',
          style: TextStyle(color: Colors.white70, fontSize: 14,
              fontWeight: FontWeight.w600)),
        if (clipCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF4FC3F7).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$clipCount clips',
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 10)),
          ),
        ],
      ]),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onOpen;
  const _EmptyState({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.videocam_outlined, color: Colors.white24, size: 64),
        const SizedBox(height: 14),
        const Text('Select your dashcam SD card or folder',
          style: TextStyle(color: Colors.white54, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('Expects video_front & video_back folders inside',
          style: TextStyle(color: Colors.white24, fontSize: 12)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onOpen,
          icon:  const Icon(Icons.folder_open_rounded),
          label: const Text('Open Drive / Folder'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4FC3F7),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(children: [
            _ShortcutRow('Space',    'Play / Pause'),
            _ShortcutRow('← →',     'Seek ±10 seconds'),
            _ShortcutRow('Shift+.', 'Next clip'),
            _ShortcutRow('Shift+,', 'Previous clip'),
          ]),
        ),
      ]),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keyLabel;
  final String label;
  const _ShortcutRow(this.keyLabel, this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(keyLabel,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
    );
  }
}