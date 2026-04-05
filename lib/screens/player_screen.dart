// lib/screens/player_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../main.dart' show launchArgs;
import '../models/layout_config.dart';
import '../models/shortcut_action.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';
import '../services/dashcam_service.dart';
import '../utils/file_pairer.dart';
import '../widgets/app_notification.dart';
import '../widgets/dual_video_view.dart';
import '../widgets/playback_controls.dart';
import '../widgets/layout_selector.dart';
import '../widgets/clip_list_drawer.dart';
import '../widgets/dashcam_overlay.dart';
import '../widgets/map_dialog.dart';
import '../widgets/shortcut_settings_dialog.dart';
import '../providers/dashcam_providers.dart';
import '../models/dashcam_state.dart';
import '../services/export_service.dart';
import '../services/log_service.dart';
import '../services/thumbnail_service.dart';

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
  bool _shiftUsedAsModifier = false;   // track Shift+key combos vs Shift alone
  bool _aboutOpen           = false;   // track About popup for toggle
  bool _dashcamOpen         = false;   // dashcam Wi-Fi overlay
  bool _isDragging          = false;   // file drag hover state
  Timer? _hideTimer;                   // auto-hide controls after inactivity
  final FocusNode _focusNode    = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _layoutBtnKey = GlobalKey();
  final GlobalKey<DualVideoViewState> _videoViewKey = GlobalKey<DualVideoViewState>();
  final GlobalKey<PlaybackControlsState> _controlsKey = GlobalKey<PlaybackControlsState>();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      final pn = ref.read(playbackProvider.notifier);
      pn.onClipEnd = _onClipEnd;
      pn.onDurationResolved = (id, dur) {
        final cache = Map.of(ref.read(clipDurationCacheProvider));
        cache[id] = dur;
        ref.read(clipDurationCacheProvider.notifier).state = cache;
      };
      // Handle file/folder passed via command-line (file association / "Open with")
      if (launchArgs.isNotEmpty) {
        _openPaths(launchArgs);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WakelockPlus.disable();
    _focusNode.dispose();
    super.dispose();
  }

  /// Show a top-right slide-in notification (replaces SnackBar).
  void _showNotification(BuildContext ctx, String message, {
    IconData? icon,
    Color? color,
    NotificationType type = NotificationType.success,
  }) {
    showAppNotification(ctx, message, icon: icon, color: color, type: type);
  }

  void _resetHideTimer() {
    if (!_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && ref.read(playbackProvider).isPlaying) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  void _handleKey(KeyEvent event) {
    final sc = ref.read(shortcutConfigProvider);
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Shift-alone fullscreen: check on key-up if Shift is bound to fullscreen
    if (event is KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
         event.logicalKey == LogicalKeyboardKey.shiftRight)) {
      if (!_shiftUsedAsModifier &&
          sc[ShortcutAction.fullscreen].keyId == 'shiftLeft') {
        appLog('Shortcut', '${sc.label(ShortcutAction.fullscreen)} – toggle fullscreen');
        _toggleFullscreen();
      }
      _shiftUsedAsModifier = false;
      return;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final key = event.logicalKey;

    // ── Escape is always hardwired ──
    if (key == LogicalKeyboardKey.escape) {
      if (_dashcamOpen) {
        setState(() => _dashcamOpen = false);
        _focusNode.requestFocus();
        return;
      }
      if ((_scaffoldKey.currentState?.isDrawerOpen ?? false) &&
          ref.read(clipSelectionModeProvider)) {
        ref.read(clipSelectionModeProvider.notifier).state = false;
        ref.read(selectedClipIndicesProvider.notifier).state = {};
        return;
      }
      if (_aboutOpen) {
        setState(() => _aboutOpen = false);
      } else {
        Navigator.of(context).maybePop();
      }
      _focusNode.requestFocus();
      return;
    }

    // Look up which action this key corresponds to
    final action = sc.actionFor(key, shift);

    // ── Global shortcuts (work even in drawers/dialogs) ──
    if (action == ShortcutAction.mapSidebar) {
      _toggleMapSidebar();
      return;
    } else if (action == ShortcutAction.clipList) {
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
      return;
    } else if (action == ShortcutAction.about) {
      setState(() => _aboutOpen = !_aboutOpen);
      return;
    } else if (action == ShortcutAction.shortcutSettings) {
      _showShortcutSettings();
      return;
    } else if (action == ShortcutAction.fullscreen &&
               sc[ShortcutAction.fullscreen].keyId != 'shiftLeft') {
      // Fullscreen remapped to a normal key (not Shift-alone)
      _toggleFullscreen();
      return;
    }

    // ── Drawer-only shortcuts ──
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      if (action == ShortcutAction.thumbnailToggle) {
        final cur = ref.read(clipViewModeProvider);
        ref.read(clipViewModeProvider.notifier).state =
            cur == ClipViewMode.text ? ClipViewMode.thumbnail : ClipViewMode.text;
        return;
      } else if (action == ShortcutAction.selectMode) {
        final next = !ref.read(clipSelectionModeProvider);
        ref.read(clipSelectionModeProvider.notifier).state = next;
        if (!next) ref.read(selectedClipIndicesProvider.notifier).state = {};
        return;
      } else if (action == ShortcutAction.selectAll &&
                 ref.read(clipSelectionModeProvider)) {
        final pairs = ref.read(videoPairListProvider);
        final sel = ref.read(selectedClipIndicesProvider);
        ref.read(selectedClipIndicesProvider.notifier).state =
            sel.length == pairs.length
                ? {}
                : Set.of(List.generate(pairs.length, (i) => i));
        return;
      }
    }

    // ── Remaining shortcuts require primary focus ──
    if (!_focusNode.hasPrimaryFocus) return;

    final playback = ref.read(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    // Mark shift as modifier so Shift-alone doesn't fire
    if (shift &&
        key != LogicalKeyboardKey.shiftLeft &&
        key != LogicalKeyboardKey.shiftRight) {
      _shiftUsedAsModifier = true;
    }

    if (action == null) return;

    switch (action) {
      case ShortcutAction.playPause:
        if (!playback.isLoaded) return;
        appLog('Shortcut', '${sc.label(action)} – toggle play/pause');
        notifier.togglePlay();
      case ShortcutAction.seekForward:
        if (!playback.isLoaded) return;
        appLog('Shortcut', '${sc.label(action)} – seek +10s');
        notifier.seekRelative(const Duration(seconds: 10));
      case ShortcutAction.seekBackward:
        if (!playback.isLoaded) return;
        appLog('Shortcut', '${sc.label(action)} – seek -10s');
        notifier.seekRelative(const Duration(seconds: -10));
      case ShortcutAction.nextClip:
        appLog('Shortcut', '${sc.label(action)} – next clip');
        _goTo(ref.read(currentIndexProvider) + 1, autoPlay: true);
      case ShortcutAction.previousClip:
        appLog('Shortcut', '${sc.label(action)} – previous clip');
        _goTo(ref.read(currentIndexProvider) - 1, autoPlay: true);
      case ShortcutAction.muteFront:
        if (!playback.isLoaded) return;
        if (playback.hasFront && !playback.hasBack) {
          final cur = ref.read(frontVolumeProvider);
          final next = cur > 0 ? 0.0 : 100.0;
          ref.read(frontVolumeProvider.notifier).state = next;
          notifier.setFrontVolume(next);
        } else if (!playback.hasFront && playback.hasBack) {
          final cur = ref.read(backVolumeProvider);
          final next = cur > 0 ? 0.0 : 100.0;
          ref.read(backVolumeProvider.notifier).state = next;
          notifier.setBackVolume(next);
        } else {
          final cur = ref.read(frontVolumeProvider);
          final next = cur > 0 ? 0.0 : 100.0;
          ref.read(frontVolumeProvider.notifier).state = next;
          notifier.setFrontVolume(next);
        }
      case ShortcutAction.muteBack:
        if (!playback.isLoaded) return;
        final cur = ref.read(backVolumeProvider);
        final next = cur > 0 ? 0.0 : 100.0;
        ref.read(backVolumeProvider.notifier).state = next;
        notifier.setBackVolume(next);
      case ShortcutAction.speedUp:
        if (!playback.isLoaded) return;
        final cur = ref.read(playbackSpeedProvider);
        final idx = playbackSpeeds.indexOf(cur);
        if (idx < playbackSpeeds.length - 1) {
          final next = playbackSpeeds[idx + 1];
          ref.read(playbackSpeedProvider.notifier).state = next;
          notifier.setSpeed(next);
        }
      case ShortcutAction.speedDown:
        if (!playback.isLoaded) return;
        final cur = ref.read(playbackSpeedProvider);
        final idx = playbackSpeeds.indexOf(cur);
        if (idx > 0) {
          final next = playbackSpeeds[idx - 1];
          ref.read(playbackSpeedProvider.notifier).state = next;
          notifier.setSpeed(next);
        }
      case ShortcutAction.speedReset:
        if (!playback.isLoaded) return;
        ref.read(playbackSpeedProvider.notifier).state = 1.0;
        notifier.setSpeed(1.0);
      case ShortcutAction.syncToggle:
        _controlsKey.currentState?.toggleSync();
      case ShortcutAction.layoutSideBySide:
        if (!playback.hasFront || !playback.hasBack) return;
        final sbsConfig = ref.read(layoutConfigProvider);
        final nextMode = sbsConfig.mode == LayoutMode.sideBySide
            ? LayoutMode.stacked
            : LayoutMode.sideBySide;
        ref.read(layoutConfigProvider.notifier).state =
            sbsConfig.copyWith(mode: nextMode);
      case ShortcutAction.layoutStacked:
        if (!playback.hasFront || !playback.hasBack) return;
        ref.read(layoutConfigProvider.notifier).state =
            ref.read(layoutConfigProvider).copyWith(mode: LayoutMode.stacked);
      case ShortcutAction.layoutPip:
        if (!playback.hasFront || !playback.hasBack) return;
        final config = ref.read(layoutConfigProvider);
        if (config.mode != LayoutMode.pip) {
          ref.read(layoutConfigProvider.notifier).state =
              config.copyWith(mode: LayoutMode.pip, pipPrimary: PipPrimary.front);
        } else {
          final next = config.pipPrimary == PipPrimary.front
              ? PipPrimary.back : PipPrimary.front;
          ref.read(layoutConfigProvider.notifier).state =
              config.copyWith(pipPrimary: next);
        }
      case ShortcutAction.layoutFrontOnly:
        if (!playback.hasFront || !playback.hasBack) return;
        final soloConfig = ref.read(layoutConfigProvider);
        if (soloConfig.mode == LayoutMode.frontOnly) {
          ref.read(layoutConfigProvider.notifier).state =
              soloConfig.copyWith(mode: LayoutMode.backOnly);
        } else {
          ref.read(layoutConfigProvider.notifier).state =
              soloConfig.copyWith(mode: LayoutMode.frontOnly);
        }
      case ShortcutAction.layoutBackOnly:
        if (!playback.hasFront || !playback.hasBack) return;
        final soloConfig2 = ref.read(layoutConfigProvider);
        if (soloConfig2.mode == LayoutMode.backOnly) {
          ref.read(layoutConfigProvider.notifier).state =
              soloConfig2.copyWith(mode: LayoutMode.frontOnly);
        } else {
          ref.read(layoutConfigProvider.notifier).state =
              soloConfig2.copyWith(mode: LayoutMode.backOnly);
        }
      case ShortcutAction.layoutPopup:
        if (!playback.hasFront || !playback.hasBack) return;
        _showLayoutPopup();
      case ShortcutAction.fullscreenAlt:
        _toggleFullscreen();
      case ShortcutAction.openFolder:
        _pickFolder();
      case ShortcutAction.saveClips:
        if (!playback.isLoaded) return;
        _saveClip();
      case ShortcutAction.deleteClips:
        if (!playback.isLoaded) return;
        _deleteClips();
      case ShortcutAction.exportVideo:
        if (!playback.isLoaded) return;
        _confirmExport();
      case ShortcutAction.closeFolder:
        _confirmCloseFolder();
      case ShortcutAction.toggleSort:
        final cur = ref.read(sortOrderProvider);
        final next = cur == SortOrder.oldestFirst
            ? SortOrder.newestFirst : SortOrder.oldestFirst;
        ref.read(sortOrderProvider.notifier).state = next;
        ref.read(videoPairListProvider.notifier).applySort(next);
        ref.read(currentIndexProvider.notifier).state = 0;
      case ShortcutAction.quit:
        _confirmQuit();
      // These are handled above in global/drawer sections
      case ShortcutAction.fullscreen:
        _toggleFullscreen();
      case ShortcutAction.shortcutSettings:
        _showShortcutSettings();
      case ShortcutAction.zoomIn:
        _videoViewKey.currentState?.zoomIn();
      case ShortcutAction.zoomOut:
        _videoViewKey.currentState?.zoomOut();
      case ShortcutAction.zoomReset:
        _videoViewKey.currentState?.resetZoom();
      case ShortcutAction.wifiDashcam:
        setState(() => _dashcamOpen = !_dashcamOpen);
        appLog('Shortcut', 'N – toggle Wi-Fi dashcam');
      case ShortcutAction.clipList:
      case ShortcutAction.mapSidebar:
      case ShortcutAction.about:
      case ShortcutAction.thumbnailToggle:
      case ShortcutAction.selectMode:
      case ShortcutAction.selectAll:
        break;
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

  Future<void> _goTo(int index, {bool autoPlay = true}) async {
    final pairs = ref.read(videoPairListProvider);
    if (index < 0 || index >= pairs.length) return;
    appLog('Playback', 'Go to clip ${index + 1}/${pairs.length} (autoPlay=$autoPlay)');
    ref.read(currentIndexProvider.notifier).state = index;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    final speed = ref.read(playbackSpeedProvider);
    final pair = pairs[index];

    // Compute sync offset: try GPS timestamps first, fall back to filename offset
    int syncOffset = pair.syncOffsetMs; // filename-based default
    if (pair.isPaired &&
        pair.frontPath != null && pair.frontPath!.toLowerCase().endsWith('.ts') &&
        pair.backPath != null && pair.backPath!.toLowerCase().endsWith('.ts')) {
      final gpsOffset = await ExportService.computeGpsSyncOffset(
          pair.frontPath!, pair.backPath!);
      if (gpsOffset != 0) {
        syncOffset = gpsOffset;
        appLog('Playback', 'GPS sync offset: ${gpsOffset}ms');
      }
    }
    if (syncOffset != 0) {
      ref.read(syncOffsetProvider.notifier).state = syncOffset;
    }

    await ref.read(playbackProvider.notifier)
        .loadPair(pair, syncOffset, autoPlay: autoPlay);

    if (speed != 1.0) {
      ref.read(playbackProvider.notifier).setSpeed(speed);
    }
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
    await _openPaths([result]);
  }

  Future<void> _pickFile() async {
    appLog('File', 'Opening file picker');
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select video file(s)',
      type: FileType.custom,
      allowedExtensions: [
        'mp4', 'mov', 'avi', 'mkv', 'ts', 'webm', 'flv',
        'wmv', 'm4v', '3gp', 'mts', 'm2ts', 'vob', 'ogv',
        'mpg', 'mpeg', 'divx', 'f4v', 'asf',
      ],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    await _openPaths(paths);
  }

  /// Shared handler for opening files/folders from any source:
  /// folder picker, drag & drop, or command-line arguments.
  Future<void> _openPaths(List<String> paths) async {
    if (paths.isEmpty) return;

    if (mounted) {
      _showNotification(context, 'Scanning for dashcam videos...',
          icon: Icons.search_rounded, type: NotificationType.warning);
    }

    final firstPath = paths.first;
    final isDir = FileSystemEntity.isDirectorySync(firstPath);

    if (isDir) {
      appLog('Folder', 'Scanning: $firstPath');
      await ref.read(videoPairListProvider.notifier).loadFromRoot(Directory(firstPath));
    } else {
      // Filter to supported video files
      final videoFiles = paths
          .where((p) => FileSystemEntity.isFileSync(p) && FilePairer.isVideoFile(p))
          .map((p) => File(p))
          .toList();
      if (videoFiles.isEmpty) {
        if (mounted) {
          _showNotification(context, 'No supported video files found',
              type: NotificationType.warning);
        }
        _focusNode.requestFocus();
        return;
      }
      appLog('Files', 'Loading ${videoFiles.length} video file(s)');
      ref.read(videoPairListProvider.notifier).loadFiles(videoFiles);
    }

    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) {
      if (mounted) {
        _showNotification(context, 'No dashcam videos found in $firstPath',
            type: NotificationType.warning);
      }
      _focusNode.requestFocus();
      return;
    }

    final paired    = pairs.where((p) => p.isPaired).length;
    final frontOnly = pairs.where((p) => p.hasFront && !p.hasBack).length;
    final backOnly  = pairs.where((p) => p.hasBack  && !p.hasFront).length;

    if (mounted) {
      _showNotification(context,
          '${pairs.length} clips  ($paired paired, $frontOnly front-only, $backOnly back-only)',
          icon: Icons.folder_open_rounded);
    }

    ref.read(currentIndexProvider.notifier).state = 0;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    ref.read(playbackSpeedProvider.notifier).state = 1.0;
    final notifier = ref.read(playbackProvider.notifier);
    notifier.onClipEnd = _onClipEnd;
    await notifier.loadPair(pairs.first, 0, autoPlay: false);
    _focusNode.requestFocus();

    // Pre-generate thumbnails in background
    final thumbPaths = <String>[];
    for (final p in pairs) {
      final vp = p.frontPath ?? p.backPath;
      if (vp != null) thumbPaths.add(vp);
    }
    ThumbnailService.pregenerate(thumbPaths);
  }

  void _toggleMapSidebar() {
    setState(() {
      _mapSidebarOpen = !_mapSidebarOpen;
      appLog('Shortcut', 'M – ${_mapSidebarOpen ? "open" : "close"} map overlay');
    });
  }

  void _showLayoutPopup() {
    final box = _layoutBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    showLayoutPopup(
      context,
      anchorRect: Rect.fromLTWH(pos.dx, pos.dy, box.size.width, box.size.height),
    ).then((_) => _focusNode.requestFocus());
  }

  Future<void> _confirmCloseFolder() async {
    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Close Folder',
        message: 'Close the current folder with ${pairs.length} clips?',
        confirmLabel: 'Close',
        confirmColor: Colors.redAccent,
      ),
    );
    if (ok != true) { _focusNode.requestFocus(); return; }
    appLog('Folder', 'Close folder (${pairs.length} clips)');
    ref.read(playbackProvider.notifier).stop();
    ref.read(videoPairListProvider.notifier).clear();
    ref.read(currentIndexProvider.notifier).state = 0;
    ref.read(syncOffsetProvider.notifier).state = 0;
    ref.read(playbackSpeedProvider.notifier).state = 1.0;
    ref.read(frontVolumeProvider.notifier).state = 100.0;
    ref.read(backVolumeProvider.notifier).state = 100.0;
    _focusNode.requestFocus();
  }

  Future<void> _confirmQuit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ConfirmDialog(
        title: 'Quit Application',
        message: 'Are you sure you want to quit?',
        confirmLabel: 'Quit',
        confirmColor: Colors.redAccent,
      ),
    );
    if (ok != true) { _focusNode.requestFocus(); return; }
    appLog('App', 'User quit');
    // Destroy window immediately — don't wait for player cleanup
    await windowManager.destroy();
    exit(0);
  }

  Future<void> _confirmExport() async {
    final pair = ref.read(currentPairProvider);
    if (pair == null) return;
    if (ref.read(exportProgressProvider) != null) return; // already exporting
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Export Video',
        message: 'Export clip "${pair.id}" with current layout settings?',
        confirmLabel: 'Export',
        confirmColor: const Color(0xFF4FC3F7),
      ),
    );
    _focusNode.requestFocus();
    if (ok != true) return;
    // Trigger the export via the controls widget's method isn't accessible,
    // so we replicate the logic here
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle:   'Save exported video',
      fileName:      'dashcam_${pair.id}.mp4',
      allowedExtensions: ['mp4'],
      type: FileType.custom,
    );
    if (savePath == null) { _focusNode.requestFocus(); return; }

    final layout     = ref.read(layoutConfigProvider);
    final syncOffset = ref.read(syncOffsetProvider);
    final pipPos     = ref.read(pipExportPositionProvider);

    ref.read(exportProgressProvider.notifier).state = 0.0;

    final exportOk = await ExportService.exportPair(
      pair:         pair,
      layout:       layout,
      syncOffsetMs: syncOffset,
      outputPath:   savePath,
      pipPosition:  pipPos,
      onProgress:   (p) =>
          ref.read(exportProgressProvider.notifier).state = p,
    );

    ref.read(exportProgressProvider.notifier).state = null;

    if (mounted) {
      if (exportOk) {
        _showNotification(context, 'Exported to $savePath',
            icon: Icons.movie_creation_rounded);
        // Open folder in explorer
        Process.run('explorer', ['/select,', savePath]);
      } else {
        _showNotification(context, 'Export failed — is FFmpeg installed?',
            type: NotificationType.error);
      }
    }
    _focusNode.requestFocus();
  }

  void _showAbout() {
    setState(() => _aboutOpen = !_aboutOpen);
  }

  void _showShortcutSettings() {
    showDialog(
      context: context,
      builder: (_) => const ShortcutSettingsDialog(),
    ).then((_) => _focusNode.requestFocus());
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

    // Count total files to copy
    int totalFiles = 0;
    for (final idx in selected) {
      final pair = pairs[idx];
      if (pair.hasFront) totalFiles++;
      if (pair.hasBack) totalFiles++;
    }

    int copied = 0;
    int failed = 0;
    ref.read(savingClipsProvider.notifier).state = '0/$totalFiles saved';

    for (final idx in selected) {
      final pair = pairs[idx];

      if (pair.isRemote) {
        // WiFi dashcam files — download via HTTP
        for (final url in [pair.frontUrl, pair.backUrl]) {
          if (url == null) continue;
          final fileName = Uri.parse(url).pathSegments.last;
          final dest = '$outDir${Platform.pathSeparator}$fileName';
          try {
            final ok = await DashcamService.downloadFile(
              remotePath: Uri.parse(url).path,
              localPath: dest,
              fileSize: 0,
              onProgress: (_) {},
            );
            if (ok) { copied++; } else { failed++; }
            ref.read(savingClipsProvider.notifier).state =
                '$copied/$totalFiles saved';
          } catch (e) {
            debugPrint('Download failed: $e');
            failed++;
          }
        }
      } else {
        // Local files — copy
        for (final file in [pair.frontFile, pair.backFile]) {
          if (file == null) continue;
          try {
            final dest = '$outDir${Platform.pathSeparator}${file.uri.pathSegments.last}';
            await file.copy(dest);
            copied++;
            ref.read(savingClipsProvider.notifier).state =
                '$copied/$totalFiles saved';
          } catch (e) {
            debugPrint('Copy failed: $e');
            failed++;
          }
        }
      }
    }

    appLog('Save', 'Saved $copied file(s), $failed failed → $outDir');
    ref.read(savingClipsProvider.notifier).state = null;
    _focusNode.requestFocus();
  }

  /// Delete clips — shows confirmation dialog, then deletes from disk and list.
  /// If [indices] is null, shows a selection dialog for current clip.
  Future<void> _deleteClips({Set<int>? indices}) async {
    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) return;

    final currentIdx = ref.read(currentIndexProvider);

    // If no indices provided, prompt the user to select from a dialog
    final toDelete = indices ?? await showDialog<Set<int>>(
      context: context,
      builder: (_) => _DeleteClipDialog(
        pairs: pairs,
        initialSelected: {currentIdx},
      ),
    );
    if (toDelete == null || toDelete.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    // Count total files
    int totalFiles = 0;
    for (final idx in toDelete) {
      final pair = pairs[idx];
      if (pair.hasFront) totalFiles++;
      if (pair.hasBack)  totalFiles++;
    }

    // Confirmation dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Delete Clips',
        message: 'Permanently delete ${toDelete.length} clip${toDelete.length > 1 ? "s" : ""}'
            ' ($totalFiles file${totalFiles > 1 ? "s" : ""}) from disk?\n\n'
            'This cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: Colors.redAccent,
      ),
    );

    if (ok != true) {
      _focusNode.requestFocus();
      return;
    }

    // Delete files from disk or dashcam
    int deleted = 0, failed = 0;
    for (final idx in toDelete) {
      final pair = pairs[idx];
      if (pair.isRemote) {
        // WiFi dashcam files — delete via API
        for (final url in [pair.frontUrl, pair.backUrl]) {
          if (url == null) continue;
          final remotePath = Uri.parse(url).path; // e.g. /mnt/card/video_front/...
          final ok = await DashcamService.deleteFile(remotePath);
          if (ok) { deleted++; } else { failed++; }
        }
      } else {
        // Local files — delete from disk
        for (final file in [pair.frontFile, pair.backFile]) {
          if (file == null) continue;
          try {
            if (await file.exists()) {
              await file.delete();
              deleted++;
            }
          } catch (e) {
            debugPrint('Delete failed: $e');
            failed++;
          }
        }
      }
    }

    appLog('Delete', 'Deleted $deleted file(s), $failed failed');

    // Remove from list
    ref.read(videoPairListProvider.notifier).removePairs(toDelete);

    // Clear selection mode
    ref.read(clipSelectionModeProvider.notifier).state = false;
    ref.read(selectedClipIndicesProvider.notifier).state = {};

    // Fix current index
    final remaining = ref.read(videoPairListProvider);
    if (remaining.isEmpty) {
      ref.read(playbackProvider.notifier).stop();
      ref.read(currentIndexProvider.notifier).state = 0;
    } else {
      final newIdx = currentIdx.clamp(0, remaining.length - 1);
      ref.read(currentIndexProvider.notifier).state = newIdx;
      await ref.read(playbackProvider.notifier)
          .loadPair(remaining[newIdx], 0, autoPlay: false);
    }

    if (mounted) {
      final msg = deleted > 0
          ? 'Deleted $deleted file${deleted != 1 ? "s" : ""}'
              '${failed > 0 ? " ($failed failed)" : ""}'
          : 'Delete failed';
      _showNotification(context, msg,
          icon: deleted > 0 ? Icons.delete_rounded : null,
          type: deleted > 0 ? NotificationType.success : NotificationType.error);
    }
    _focusNode.requestFocus();
  }

  /// Called from the drawer's save button — uses the drawer's selection.
  Future<void> _saveFromDrawer() async {
    final selected = ref.read(selectedClipIndicesProvider);
    if (selected.isEmpty) return;

    final pairs = ref.read(videoPairListProvider);

    // Close drawer
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    // Pick save location
    final outDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder to save clips',
    );
    if (outDir == null) {
      _focusNode.requestFocus();
      return;
    }

    int totalFiles = 0;
    for (final idx in selected) {
      final pair = pairs[idx];
      if (pair.hasFront) totalFiles++;
      if (pair.hasBack)  totalFiles++;
    }

    int copied = 0, failed = 0;
    ref.read(savingClipsProvider.notifier).state = '0/$totalFiles saved';

    for (final idx in selected) {
      final pair = pairs[idx];

      if (pair.isRemote) {
        // WiFi dashcam files — download via HTTP
        for (final url in [pair.frontUrl, pair.backUrl]) {
          if (url == null) continue;
          final fileName = Uri.parse(url).pathSegments.last;
          final dest = '$outDir${Platform.pathSeparator}$fileName';
          try {
            final ok = await DashcamService.downloadFile(
              remotePath: Uri.parse(url).path,
              localPath: dest,
              fileSize: 0,
              onProgress: (_) {},
            );
            if (ok) { copied++; } else { failed++; }
            ref.read(savingClipsProvider.notifier).state = '$copied/$totalFiles saved';
          } catch (e) {
            debugPrint('Download failed: $e');
            failed++;
          }
        }
      } else {
        for (final file in [pair.frontFile, pair.backFile]) {
          if (file == null) continue;
          try {
            final dest = '$outDir${Platform.pathSeparator}${file.uri.pathSegments.last}';
            await file.copy(dest);
            copied++;
            ref.read(savingClipsProvider.notifier).state = '$copied/$totalFiles saved';
          } catch (e) {
            debugPrint('Copy failed: $e');
            failed++;
          }
        }
      }
    }

    appLog('Save', 'Saved $copied file(s), $failed failed → $outDir');
    ref.read(savingClipsProvider.notifier).state = null;

    // Clear selection
    ref.read(clipSelectionModeProvider.notifier).state = false;
    ref.read(selectedClipIndicesProvider.notifier).state = {};
    _focusNode.requestFocus();
  }

  /// Called from the drawer's delete button.
  Future<void> _deleteFromDrawer(Set<int> indices) async {
    // Close drawer first
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    await _deleteClips(indices: indices);
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
          if (!open) _focusNode.requestFocus();
        },
        drawer: pairs.isNotEmpty ? ClipListDrawer(
          onSelect: (i) {
            _goTo(i, autoPlay: true);
          },
          onSave:   _saveFromDrawer,
          onDelete:  _deleteFromDrawer,
        ) : null,
        endDrawer: null,
        body: pairs.isEmpty
          ? _buildLandingBody()
          : MouseRegion(
          onHover: (_) => _resetHideTimer(),
          child: Column(children: [
          // Top bar — collapses when hidden so video fills space
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _overlayVisible
                ? _MinimalTopBar(
                    clipCount:          pairs.length,
                    isFullscreen:       _isFullscreen,
                    onToggleFullscreen: _toggleFullscreen,
                    onAbout:            _showAbout,
                    onShortcutSettings: _showShortcutSettings,
                    onDashcam: () => setState(() => _dashcamOpen = !_dashcamOpen),
                  )
                : const SizedBox.shrink(),
          ),

          // Video area — tap toggles controls visibility
          Expanded(
            child: GestureDetector(
              onTap: () {
                _focusNode.requestFocus();
                if (_overlayVisible) {
                  _hideTimer?.cancel();
                  setState(() => _overlayVisible = false);
                } else {
                  _resetHideTimer();
                }
              },
              child: Stack(children: [
                Row(children: [
                  Expanded(child: DualVideoView(key: _videoViewKey)),
                  if (_mapSidebarOpen)
                    MapPanel(
                      videoPath: mapVideoPath,
                      onClose: () {
                        setState(() => _mapSidebarOpen = false);
                        _focusNode.requestFocus();
                      },
                    ),
                ]),
                // About overlay — rendered in-widget so I key toggle works
                if (_aboutOpen)
                  GestureDetector(
                    onTap: () => setState(() => _aboutOpen = false),
                    child: Container(
                      color: Colors.black38,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: GestureDetector(
                        onTap: () {}, // absorb taps on the panel
                        child: const _AboutPanel(),
                      ),
                    ),
                  ),
                // Dashcam Wi-Fi overlay
                if (_dashcamOpen)
                  GestureDetector(
                    onTap: () => setState(() => _dashcamOpen = false),
                    child: Container(
                      color: Colors.black54,
                      child: GestureDetector(
                        onTap: () {}, // absorb taps on the panel
                        child: DashcamOverlay(
                          onClose: () {
                            setState(() => _dashcamOpen = false);
                            _focusNode.requestFocus();
                          },
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),

          // Controls bar — collapses when hidden so video fills space
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _overlayVisible
                ? PlaybackControls(
                    key: _controlsKey,
                    onPrevious:     () => _goTo(ref.read(currentIndexProvider) - 1, autoPlay: true),
                    onNext:         () => _goTo(ref.read(currentIndexProvider) + 1, autoPlay: true),
                    onFolder:       _pickFolder,
                    onLayout:       _showLayoutPopup,
                    layoutBtnKey:   _layoutBtnKey,
                    onSaveClip:     _saveClip,
                    onCloseFolder:  _confirmCloseFolder,
                    onQuit:         _confirmQuit,
                    onMap:          _toggleMapSidebar,
                    onZoomIn:       () => _videoViewKey.currentState?.zoomIn(),
                    onZoomOut:      () => _videoViewKey.currentState?.zoomOut(),
                    focusRequester: _focusNode.requestFocus,
                  )
                : const SizedBox.shrink(),
          ),
        ]),
        ),
      ),
    );
  }

  // ─── Landing page (no clips loaded) ─────────────────────────────────────────

  Widget _buildLandingBody() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited:  (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final paths = details.files.map((f) => f.path).toList();
        _openPaths(paths);
      },
      child: Row(
      children: [
        // ─── Left Sidebar ───
        Container(
          width: 200,
          decoration: const BoxDecoration(
            color: Color(0xFF0D1117),
            border: Border(right: BorderSide(color: Color(0xFF1E2630))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App branding
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.videocam_rounded,
                        color: Color(0xFF4FC3F7), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('DashCam Player',
                      style: TextStyle(color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
              // Navigation items
              _landingNavItem(Icons.folder_rounded, 'Library', true, _pickFolder),
              _landingNavItem(Icons.access_time_rounded, 'Recent Videos', false, null),
              _landingNavItem(Icons.location_on_outlined, 'Map View', false, null),
              _landingNavItem(Icons.settings_outlined, 'Settings', false, _showShortcutSettings),
              const Spacer(),
            ],
          ),
        ),

        // ─── Main Content ───
        Expanded(
          child: Column(children: [
            // Top bar with action icons
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded,
                        color: Colors.white38, size: 20),
                    onPressed: () {},
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.help_outline_rounded,
                        color: Colors.white38, size: 20),
                    onPressed: _showAbout,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: Colors.white38, size: 20),
                    onPressed: () {},
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white38, size: 20),
                    onPressed: _showShortcutSettings,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Hero area
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0A1628),
                      Color(0xFF0F1D32),
                      Color(0xFF0A1628),
                      Color(0xFF060C16),
                    ],
                  ),
                ),
                child: Stack(children: [
                  // Subtle atmosphere lines
                  Positioned.fill(
                    child: CustomPaint(painter: _RoadAtmospherePainter()),
                  ),
                  // Center content
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Layout mode toggle (Front | Split | Rear)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _landingLayoutTab(Icons.videocam_outlined, 'Front', false),
                              _landingLayoutTab(Icons.view_column_outlined, 'Split', true),
                              _landingLayoutTab(Icons.videocam_outlined, 'Rear', false),
                            ],
                          ),
                        ),
                        const SizedBox(height: 48),
                        // Download icon in bordered box
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _isDragging
                                  ? const Color(0xFF4FC3F7)
                                  : const Color(0xFF4FC3F7).withValues(alpha: 0.3),
                              width: _isDragging ? 2.0 : 1.5,
                            ),
                            color: _isDragging
                                ? const Color(0xFF4FC3F7).withValues(alpha: 0.15)
                                : const Color(0xFF4FC3F7).withValues(alpha: 0.06),
                          ),
                          child: Icon(
                            _isDragging ? Icons.file_download_rounded : Icons.download_rounded,
                            color: const Color(0xFF4FC3F7), size: 32),
                        ),
                        const SizedBox(height: 28),
                        // Open Dashcam Folder button
                        ElevatedButton.icon(
                          onPressed: _pickFolder,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Open Dashcam Folder',
                              style: TextStyle(fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4FC3F7),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 8,
                            shadowColor:
                                const Color(0xFF4FC3F7).withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.video_file_outlined, size: 18),
                          label: const Text('Open Video File',
                              style: TextStyle(fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4FC3F7),
                            side: BorderSide(
                                color: const Color(0xFF4FC3F7).withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: _isDragging
                                ? const Color(0xFF4FC3F7)
                                : Colors.white.withValues(alpha: 0.35),
                            fontSize: 13,
                            fontWeight: _isDragging ? FontWeight.w600 : FontWeight.w400,
                          ),
                          child: Text(_isDragging
                              ? 'Drop to open'
                              : 'or Drag & Drop videos here'),
                        ),
                      ],
                    ),
                  ),
                  // Drag overlay border
                  if (_isDragging)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF4FC3F7).withValues(alpha: 0.5),
                              width: 2,
                            ),
                            color: const Color(0xFF4FC3F7).withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),

            // Quick action cards — row 1
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(children: [
                Expanded(
                    child: _landingActionCard(
                  Icons.history_rounded,
                  const Color(0xFF4FC3F7),
                  'Resume Last Session',
                  'Start where you left off',
                  _pickFolder,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _landingActionCard(
                  Icons.folder_open_rounded,
                  const Color(0xFF26A69A),
                  'Open Recent Folder',
                  'Browse dashcam folders',
                  _pickFolder,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _landingActionCard(
                  Icons.movie_creation_outlined,
                  const Color(0xFF5C6BC0),
                  'Export Last Clip',
                  'MP4 video export',
                  null,
                )),
              ]),
            ),
            // Quick action cards — row 2
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: [
                Expanded(
                    child: _landingActionCard(
                  Icons.wifi_rounded,
                  const Color(0xFF42A5F5),
                  'Connect Wi-Fi Dashcam',
                  'Download from camera',
                  () => setState(() => _dashcamOpen = !_dashcamOpen),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _landingActionCard(
                  Icons.route_rounded,
                  const Color(0xFFEF5350),
                  'View GPS Route',
                  'Map & location data',
                  null,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _landingActionCard(
                  Icons.keyboard_rounded,
                  const Color(0xFFAB47BC),
                  'Keyboard Shortcuts',
                  'View all shortcuts',
                  _showShortcutSettings,
                )),
              ]),
            ),

            // Bottom controls bar (disabled placeholder)
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF0A0A0A),
                border: Border(top: BorderSide(color: Color(0xFF1A1A1A))),
              ),
              child: Row(children: [
                const Icon(Icons.replay_10_rounded,
                    color: Colors.white12, size: 20),
                const SizedBox(width: 12),
                Icon(Icons.play_arrow_rounded,
                    color: Colors.white.withValues(alpha: 0.16), size: 28),
                const SizedBox(width: 12),
                const Icon(Icons.forward_10_rounded,
                    color: Colors.white12, size: 20),
                const SizedBox(width: 16),
                const Icon(Icons.volume_up_rounded,
                    color: Colors.white12, size: 18),
                const SizedBox(width: 16),
                // Progress bar
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text('00:00',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.16),
                        fontSize: 12,
                        fontFamily: 'monospace')),
                const SizedBox(width: 12),
                Text('00:00',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.16),
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ]),
            ),
          ]),
        ),
      ],
    ),
    );
  }

  Widget _landingNavItem(
      IconData icon, String label, bool selected, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF4FC3F7).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(icon,
                color: selected
                    ? const Color(0xFF4FC3F7)
                    : Colors.white38,
                size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                )),
          ]),
        ),
      ),
    );
  }

  Widget _landingActionCard(IconData icon, Color color, String title,
      String subtitle, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: onTap != null ? 1.0 : 0.5,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111820),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2630)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11)),
                ],
              )),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.2), size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  static Widget _landingLayoutTab(IconData icon, String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF4FC3F7) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: selected ? Colors.black : Colors.white38),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white38,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
        ],
      ),
    );
  }
}

// ─── Minimal top bar ──────────────────────────────────────────────────────────

class _MinimalTopBar extends ConsumerWidget {
  final int          clipCount;
  final bool         isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onAbout;
  final VoidCallback? onShortcutSettings;
  final VoidCallback? onDashcam;
  const _MinimalTopBar({
    required this.clipCount,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    this.onAbout,
    this.onShortcutSettings,
    this.onDashcam,
  });

  static String _extractFileName(String? path) {
    if (path == null || path.isEmpty) return '';
    final sep = path.contains('\\') ? '\\' : '/';
    return path.split(sep).last;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(shortcutConfigProvider);
    final currentPair = ref.watch(currentPairProvider);
    final currentFileName = currentPair != null
        ? _extractFileName(currentPair.frontPath ?? currentPair.backPath)
        : '';

    return Container(
      color: const Color(0xCC000000),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 2,
        left: 4, right: 4, bottom: 2,
      ),
      child: Row(children: [
        // Left: menu + title + badge + filename (takes remaining space)
        Expanded(
          child: Row(children: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white60),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Clip list (${sc.label(ShortcutAction.clipList)})',
                iconSize: 20,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(width: 4),
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
            if (currentFileName.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(currentFileName,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ]),
        ),
        // Right: action icons (fixed, always top-right)
        _DashcamStatusBtn(onTap: onDashcam),
        IconButton(
          icon: const Icon(Icons.keyboard_rounded, color: Colors.white38),
          onPressed: onShortcutSettings,
          tooltip: 'Keyboard shortcuts',
          iconSize: 18,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline_rounded, color: Colors.white38),
          onPressed: onAbout,
          tooltip: 'About (${sc.label(ShortcutAction.about)})',
          iconSize: 18,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
        ),
        IconButton(
          icon: Icon(
            isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            color: Colors.white54,
          ),
          onPressed: onToggleFullscreen,
          tooltip: isFullscreen
              ? 'Exit fullscreen (${sc.label(ShortcutAction.fullscreen)})'
              : 'Fullscreen (${sc.label(ShortcutAction.fullscreen)})',
          iconSize: 20,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
      ]),
    );
  }
}

class _DashcamStatusBtn extends ConsumerWidget {
  final VoidCallback? onTap;
  const _DashcamStatusBtn({this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dashcamProvider).status;
    final (color, tip) = switch (status) {
      DashcamConnectionStatus.connected => (const Color(0xFF4FC3F7), 'Dashcam connected'),
      DashcamConnectionStatus.connecting => (Colors.amber, 'Connecting to dashcam...'),
      DashcamConnectionStatus.error => (Colors.redAccent, 'Dashcam connection error'),
      _ => (Colors.white38, 'Dashcam Wi-Fi'),
    };
    return Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(Icons.wifi_rounded, color: color),
        onPressed: onTap,
        iconSize: 18,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

// ─── About panel (in-widget overlay, not a dialog) ───────────────────────────

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.videocam_rounded,
                  color: Color(0xFF4FC3F7), size: 24),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DashCam Player',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text('v2.0.0  \u00b7  Desktop',
                    style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 11)),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 14),
          const _Af(Icons.play_circle_outline_rounded, 'Synchronized dual-camera playback'),
          const _Af(Icons.view_quilt_rounded, 'Side-by-side, Stacked & PIP layouts'),
          const _Af(Icons.picture_in_picture_rounded, 'Draggable & resizable PIP overlay'),
          const _Af(Icons.speed_rounded, 'Variable speed playback (0.1x \u2013 5x)'),
          const _Af(Icons.map_rounded, 'GPS & interactive OpenStreetMap'),
          const _Af(Icons.movie_creation_rounded, 'FFmpeg video export & composition'),
          const _Af(Icons.save_alt_rounded, 'Batch save clips with progress'),
          const _Af(Icons.sync_rounded, 'Manual audio sync offset (\u00b15s)'),
          const _Af(Icons.keyboard_rounded, '20+ keyboard shortcuts'),
          const SizedBox(height: 14),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          const Text('Built with Flutter & media_kit',
              style: TextStyle(color: Colors.white30, fontSize: 10)),
          const Text('Press I to close',
              style: TextStyle(color: Colors.white24, fontSize: 10)),
        ],
      ),
    );
  }
}

class _Af extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Af(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF4FC3F7), size: 14),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: const TextStyle(color: Colors.white60, fontSize: 12))),
      ]),
    );
  }
}

// ─── Confirmation dialog with Enter/Escape support ──────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          Navigator.pop(context, true);
        }
      },
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(message,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
  }
}

// ─── Landing page (empty state) ─────────────────────────────────────────────

class _RoadAtmospherePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;

    // Converging perspective lines (road vanishing point effect)
    final cx = size.width / 2;
    final vanishY = size.height * 0.35;

    paint.color = const Color(0x06FFFFFF);
    for (var i = 1; i <= 6; i++) {
      final spread = i * size.width * 0.12;
      final y = vanishY + i * size.height * 0.08;
      canvas.drawLine(Offset(cx - spread, y), Offset(cx + spread, y), paint);
    }

    // Center dashed line (road markings)
    paint.color = const Color(0x0AFFFFFF);
    for (var i = 0; i < 8; i++) {
      final y = vanishY + 20 + i * 22.0;
      final halfW = 4.0 + i * 3.0;
      canvas.drawLine(Offset(cx - halfW, y), Offset(cx + halfW, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                final isSingleVideo = pair.hasFront && !pair.hasBack && !pair.isRemote && pair.source == 'local';
                final badge = pair.isPaired
                    ? 'F+B'
                    : isSingleVideo
                        ? 'Video'
                        : pair.hasFront
                            ? 'F only'
                            : 'B only';
                final badgeColor = pair.isPaired
                    ? const Color(0xFF4FC3F7)
                    : isSingleVideo
                        ? Colors.teal
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
                    if (pair.isRemote) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.wifi_rounded, size: 10, color: Color(0xFF4FC3F7)),
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

// ─── Delete clip dialog (D shortcut) ────────────────────────────────────────

class _DeleteClipDialog extends StatefulWidget {
  final List<VideoPair> pairs;
  final Set<int> initialSelected;
  const _DeleteClipDialog({required this.pairs, required this.initialSelected});

  @override
  State<_DeleteClipDialog> createState() => _DeleteClipDialogState();
}

class _DeleteClipDialogState extends State<_DeleteClipDialog> {
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
              const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Delete Clips',
                  style: TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w600)),
              ),
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
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
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
                final isSingleVideo = pair.hasFront && !pair.hasBack && !pair.isRemote && pair.source == 'local';
                final badge = pair.isPaired
                    ? 'F+B'
                    : isSingleVideo
                        ? 'Video'
                        : pair.hasFront
                            ? 'F only'
                            : 'B only';
                final badgeColor = pair.isPaired
                    ? const Color(0xFF4FC3F7)
                    : isSingleVideo
                        ? Colors.teal
                        : pair.hasFront
                            ? Colors.orange
                            : Colors.purple;

                return CheckboxListTile(
                  value: checked,
                  activeColor: Colors.redAccent,
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
                    if (pair.isRemote) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.wifi_rounded, size: 10, color: Color(0xFF4FC3F7)),
                    ],
                  ]),
                  dense: true,
                );
              },
            ),
          ),

          // Footer with delete button
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
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
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
