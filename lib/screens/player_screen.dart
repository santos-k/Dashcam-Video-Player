// lib/screens/player_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';
import '../widgets/dual_video_view.dart';
import '../widgets/playback_controls.dart';
import '../widgets/layout_selector.dart';
import '../widgets/clip_list_drawer.dart';
import '../widgets/map_dialog.dart';
import '../services/log_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _overlayVisible      = true;
  bool _isFullscreen        = false;
  bool _fullscreenTransiting = false;
  bool _mapSidebarOpen      = false;
  final FocusNode _focusNode    = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      ref.read(playbackProvider.notifier).onClipEnd = _onClipEnd;
    });
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
      appLog('Shortcut', 'Space – toggle play/pause');
      notifier.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowRight && playback.isLoaded) {
      appLog('Shortcut', 'Right arrow – seek +10s');
      notifier.seekRelative(const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.arrowLeft && playback.isLoaded) {
      appLog('Shortcut', 'Left arrow – seek -10s');
      notifier.seekRelative(const Duration(seconds: -10));
    } else if ((key == LogicalKeyboardKey.period && shift) ||
               key == LogicalKeyboardKey.greater) {
      appLog('Shortcut', 'Shift+. – next clip');
      _goTo(ref.read(currentIndexProvider) + 1, autoPlay: true);
    } else if ((key == LogicalKeyboardKey.comma && shift) ||
               key == LogicalKeyboardKey.less) {
      appLog('Shortcut', 'Shift+, – previous clip');
      _goTo(ref.read(currentIndexProvider) - 1, autoPlay: true);
    } else if (key == LogicalKeyboardKey.keyF) {
      final next = !ref.read(frontMutedProvider);
      appLog('Shortcut', 'F – ${next ? "mute" : "unmute"} front');
      ref.read(frontMutedProvider.notifier).state = next;
      notifier.setFrontMuted(next);
    } else if (key == LogicalKeyboardKey.keyB) {
      final next = !ref.read(backMutedProvider);
      appLog('Shortcut', 'B – ${next ? "mute" : "unmute"} back');
      ref.read(backMutedProvider.notifier).state = next;
      notifier.setBackMuted(next);
    } else if (key == LogicalKeyboardKey.keyM && !shift) {
      // 'M': single-camera mute toggle when unpaired, map when paired or no video
      if (playback.isLoaded && playback.hasFront && !playback.hasBack) {
        final next = !ref.read(frontMutedProvider);
        ref.read(frontMutedProvider.notifier).state = next;
        notifier.setFrontMuted(next);
      } else if (playback.isLoaded && playback.hasBack && !playback.hasFront) {
        final next = !ref.read(backMutedProvider);
        ref.read(backMutedProvider.notifier).state = next;
        notifier.setBackMuted(next);
      } else {
        // Paired or no video — toggle map sidebar
        _toggleMapSidebar();
      }
    } else if (key == LogicalKeyboardKey.keyO) {
      appLog('Shortcut', 'O – open folder');
      _pickFolder();
    } else if (key == LogicalKeyboardKey.keyL &&
               playback.hasFront && playback.hasBack) {
      appLog('Shortcut', 'L – layout selector');
      showLayoutSelector(context).then((_) => _focusNode.requestFocus());
    } else if (key == LogicalKeyboardKey.keyS) {
      appLog('Shortcut', 'S – toggle sort order');
      final current = ref.read(sortOrderProvider);
      final next    = current == SortOrder.oldestFirst
          ? SortOrder.newestFirst
          : SortOrder.oldestFirst;
      ref.read(sortOrderProvider.notifier).state = next;
      ref.read(videoPairListProvider.notifier).applySort(next);
      ref.read(currentIndexProvider.notifier).state = 0;
    } else if (key == LogicalKeyboardKey.keyW) {
      appLog('Shortcut', 'W – close folder');
      _closeFolder();
    } else if (key == LogicalKeyboardKey.f11 ||
               key == LogicalKeyboardKey.enter) {
      appLog('Shortcut', '${key == LogicalKeyboardKey.f11 ? "F11" : "Enter"} – toggle fullscreen');
      _toggleFullscreen();
    }
  }

  void _toggleFullscreen() {
    if (_fullscreenTransiting) return; // debounce rapid presses
    _fullscreenTransiting = true;

    final next = !_isFullscreen;
    appLog('UI', 'Fullscreen ${next ? "enter" : "exit"}');

    // Update state immediately so the UI reflects the change without
    // waiting for the window manager.
    setState(() => _isFullscreen = next);

    // Fire-and-forget: don't await to avoid blocking the UI / video.
    windowManager.setFullScreen(next).then((_) {
      // Restore focus after the window finishes resizing.
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _focusNode.requestFocus();
        _fullscreenTransiting = false;
      });
    });
  }

  void _goTo(int index, {bool autoPlay = true}) {
    final pairs = ref.read(videoPairListProvider);
    if (index < 0 || index >= pairs.length) return;
    appLog('Playback', 'Go to clip ${index + 1}/${pairs.length} (autoPlay=$autoPlay)');
    ref.read(currentIndexProvider.notifier).state = index;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    ref.read(playbackProvider.notifier).loadPair(pairs[index], 0, autoPlay: autoPlay);
  }

  void _onClipEnd() {
    appLog('Playback', 'Clip ended');
    final pairs = ref.read(videoPairListProvider);
    final index = ref.read(currentIndexProvider);
    final next  = index + 1;
    if (next < pairs.length) {
      _goTo(next, autoPlay: true);
    }
  }

  Future<void> _pickFolder() async {
    appLog('Folder', 'Opening folder picker');
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select dashcam drive or folder',
    );
    if (result == null) {
      _focusNode.requestFocus();
      return;
    }

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

    appLog('Folder', 'Scanning: $result');
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
      _focusNode.requestFocus();
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
    final notifier = ref.read(playbackProvider.notifier);
    notifier.onClipEnd = _onClipEnd;
    await notifier.loadPair(pairs.first, 0, autoPlay: false);
    _focusNode.requestFocus();
  }

  void _toggleMapSidebar() {
    if (_mapSidebarOpen) {
      appLog('Shortcut', 'M – close map sidebar');
      Navigator.of(context).maybePop();
      _focusNode.requestFocus();
    } else {
      appLog('Shortcut', 'M – open map sidebar');
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  void _closeFolder() {
    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) return;
    appLog('Folder', 'Close folder (${pairs.length} clips)');
    ref.read(playbackProvider.notifier).stop();
    ref.read(videoPairListProvider.notifier).clear();
    ref.read(currentIndexProvider.notifier).state = 0;
    ref.read(syncOffsetProvider.notifier).state = 0;
    ref.read(frontMutedProvider.notifier).state = false;
    ref.read(backMutedProvider.notifier).state = false;
    _focusNode.requestFocus();
  }

  Future<void> _saveClip() async {
    appLog('Save', 'Save dialog opened');
    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) return;

    final currentIdx = ref.read(currentIndexProvider);

    // Show clip-selection dialog
    final selected = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _SaveClipDialog(
        pairs: pairs,
        initialSelected: {currentIdx},
      ),
    );
    if (selected == null || selected.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    // Pick save location
    final outDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder to save clips',
    );
    if (outDir == null) {
      _focusNode.requestFocus();
      return;
    }

    ref.read(savingClipsProvider.notifier).state = true;

    int copied = 0;
    int failed = 0;

    for (final idx in selected) {
      final pair = pairs[idx];
      for (final file in [pair.frontFile, pair.backFile]) {
        if (file == null) continue;
        try {
          final dest = '$outDir${Platform.pathSeparator}${file.uri.pathSegments.last}';
          await file.copy(dest);
          copied++;
        } catch (e) {
          debugPrint('Copy failed: $e');
          failed++;
        }
      }
    }

    appLog('Save', 'Copied $copied file(s), $failed failed → $outDir');
    ref.read(savingClipsProvider.notifier).state = false;
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final pairs = ref.watch(videoPairListProvider);

    final currentPair = pairs.isNotEmpty
        ? pairs[ref.watch(currentIndexProvider).clamp(0, pairs.length - 1)]
        : null;
    final mapVideoPath = currentPair?.frontPath ?? currentPair?.backPath;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        onEndDrawerChanged: (open) {
          _mapSidebarOpen = open;
          if (!open) _focusNode.requestFocus();
        },
        drawer: ClipListDrawer(
          onSelect: (i) {
            _goTo(i, autoPlay: true);
          },
        ),
        endDrawer: MapSidebar(
          videoPath: mapVideoPath,
          onClose: () => _focusNode.requestFocus(),
        ),
        body: Column(children: [
          _MinimalTopBar(
            clipCount:          pairs.length,
            isFullscreen:       _isFullscreen,
            onToggleFullscreen: _toggleFullscreen,
          ),

          // Video area — tap toggles controls visibility
          Expanded(
            child: GestureDetector(
              onTap: () {
                _focusNode.requestFocus();
                setState(() => _overlayVisible = !_overlayVisible);
              },
              child: Stack(children: [
                const DualVideoView(),
                if (pairs.isEmpty) _EmptyState(onOpen: _pickFolder),
              ]),
            ),
          ),

          // Controls bar — slides out below screen when hidden
          AnimatedSlide(
            offset:   _overlayVisible ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 200),
            child: PlaybackControls(
              onPrevious:     () => _goTo(ref.read(currentIndexProvider) - 1, autoPlay: true),
              onNext:         () => _goTo(ref.read(currentIndexProvider) + 1, autoPlay: true),
              onFolder:       _pickFolder,
              onLayout:       () => showLayoutSelector(context)
                  .then((_) => _focusNode.requestFocus()),
              onSaveClip:     _saveClip,
              onCloseFolder:  _closeFolder,
              onMap:          _toggleMapSidebar,
              focusRequester: _focusNode.requestFocus,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Minimal top bar ──────────────────────────────────────────────────────────

class _MinimalTopBar extends StatelessWidget {
  final int          clipCount;
  final bool         isFullscreen;
  final VoidCallback onToggleFullscreen;
  const _MinimalTopBar({
    required this.clipCount,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC000000),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 2,
        left: 4, right: 4, bottom: 2,
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
              color: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$clipCount clips',
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 10)),
          ),
        ],
        const Spacer(),
        Tooltip(
          message: isFullscreen ? 'Exit fullscreen (F11)' : 'Fullscreen (F11)',
          child: IconButton(
            icon: Icon(
              isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white54,
            ),
            onPressed: onToggleFullscreen,
            iconSize: 20,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(width: 4),
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
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(children: [
            _ShortcutRow('Space',    'Play / Pause'),
            _ShortcutRow('← →',     'Seek ±10 seconds'),
            _ShortcutRow('Shift+.', 'Next clip'),
            _ShortcutRow('Shift+,', 'Previous clip'),
            _ShortcutRow('F / B',   'Mute front / back (paired)'),
            _ShortcutRow('M',       'Mute (single) / Map (paired)'),
            _ShortcutRow('O',       'Open folder'),
            _ShortcutRow('L',       'Change layout'),
            _ShortcutRow('S',       'Toggle sort order'),
            _ShortcutRow('W',       'Close folder'),
            _ShortcutRow('F11',     'Toggle fullscreen'),
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

// ─── Save clip dialog ────────────────────────────────────────────────────────

class _SaveClipDialog extends StatefulWidget {
  final List<VideoPair> pairs;
  final Set<int> initialSelected;
  const _SaveClipDialog({required this.pairs, required this.initialSelected});

  @override
  State<_SaveClipDialog> createState() => _SaveClipDialogState();
}

class _SaveClipDialogState extends State<_SaveClipDialog> {
  late final Set<int> _selected;
  final _fmt = DateFormat('MMM d, yyyy  HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.initialSelected);
  }

  int get _totalFiles {
    int count = 0;
    for (final idx in _selected) {
      final p = widget.pairs[idx];
      if (p.hasFront) count++;
      if (p.hasBack) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              const Icon(Icons.save_alt_rounded, color: Color(0xFF4FC3F7), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Save Clips',
                  style: TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w600)),
              ),
              // Select all / none
              TextButton(
                onPressed: () => setState(() {
                  if (_selected.length == widget.pairs.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(
                      List.generate(widget.pairs.length, (i) => i));
                  }
                }),
                child: Text(
                  _selected.length == widget.pairs.length
                      ? 'Deselect all'
                      : 'Select all',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF4FC3F7)),
                ),
              ),
            ]),
          ),

          // Clip list
          Expanded(
            child: ListView.builder(
              itemCount: widget.pairs.length,
              itemBuilder: (_, i) {
                final pair = widget.pairs[i];
                final checked = _selected.contains(i);
                final fileCount = (pair.hasFront ? 1 : 0) + (pair.hasBack ? 1 : 0);
                final badge = pair.isPaired
                    ? 'F+B'
                    : pair.hasFront
                        ? 'F only'
                        : 'B only';
                final badgeColor = pair.isPaired
                    ? const Color(0xFF4FC3F7)
                    : pair.hasFront
                        ? Colors.orange
                        : Colors.purple;

                return CheckboxListTile(
                  value: checked,
                  activeColor: const Color(0xFF4FC3F7),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(i);
                    } else {
                      _selected.remove(i);
                    }
                  }),
                  title: Text(
                    _fmt.format(pair.timestamp),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  subtitle: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(badge,
                        style: TextStyle(color: badgeColor, fontSize: 10,
                            fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Text('$fileCount file${fileCount > 1 ? "s" : ""}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    if (pair.isLocked) ...[
                      const SizedBox(width: 4),
                      const Text('locked',
                        style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                    ],
                  ]),
                  dense: true,
                );
              },
            ),
          ),

          // Footer with save button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(children: [
              Text(
                '${_selected.length} clip${_selected.length != 1 ? "s" : ""}'
                ' selected  ($_totalFiles file${_totalFiles != 1 ? "s" : ""})',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected),
                icon: const Icon(Icons.save_alt_rounded, size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
