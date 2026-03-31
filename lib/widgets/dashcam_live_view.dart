// lib/widgets/dashcam_live_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../providers/dashcam_providers.dart';
import '../services/dashcam_service.dart';

class DashcamLiveView extends ConsumerStatefulWidget {
  const DashcamLiveView({super.key});

  @override
  ConsumerState<DashcamLiveView> createState() => _DashcamLiveViewState();
}

class _DashcamLiveViewState extends ConsumerState<DashcamLiveView> {
  // Front stream
  Player? _frontPlayer;
  VideoController? _frontController;
  // Back stream
  Player? _backPlayer;
  VideoController? _backController;

  bool _streaming = false;
  bool _connecting = false;
  String? _error;
  late String _currentUrl;
  bool _sideBySide = true; // default to side-by-side for dual cam
  int _activeCamera = 0; // 0=front, 1=back (for single view mode)

  @override
  void initState() {
    super.initState();
    final mediaInfo = ref.read(dashcamProvider).mediaInfo;
    _currentUrl = mediaInfo?.rtsp.isNotEmpty == true
        ? '${mediaInfo!.rtsp}:${mediaInfo.port}'
        : DashcamService.rtspUrl;
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  Future<Player> _createPlayer() async {
    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 0,
        logLevel: MPVLogLevel.v,
      ),
    );
    // Force RTSP over TCP
    try {
      final nativePlayer = player.platform as NativePlayer;
      await nativePlayer.setProperty('rtsp-transport', 'tcp');
    } catch (_) {}
    return player;
  }

  Future<void> _startStream() async {
    if (_connecting) return;
    setState(() { _connecting = true; _error = null; });

    // Stop recording first — dashcam can't record and stream simultaneously
    try {
      await ref.read(dashcamProvider.notifier).stopRecording();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {}

    try {
      if (_sideBySide) {
        // Side-by-side: open two streams
        // Switch to front, open front stream
        await DashcamService.switchCamera(0);
        await Future.delayed(const Duration(milliseconds: 300));

        _frontPlayer = await _createPlayer();
        _frontController = VideoController(_frontPlayer!);
        debugPrint('DashcamLiveView: opening front stream $_currentUrl');
        await _frontPlayer!.open(Media(_currentUrl), play: true);

        // Switch to back, open back stream
        await DashcamService.switchCamera(1);
        await Future.delayed(const Duration(milliseconds: 300));

        _backPlayer = await _createPlayer();
        _backController = VideoController(_backPlayer!);
        debugPrint('DashcamLiveView: opening back stream $_currentUrl');
        await _backPlayer!.open(Media(_currentUrl), play: true);
      } else {
        // Single view: one stream for selected camera
        await DashcamService.switchCamera(_activeCamera);
        await Future.delayed(const Duration(milliseconds: 300));

        _frontPlayer = await _createPlayer();
        _frontController = VideoController(_frontPlayer!);
        debugPrint('DashcamLiveView: opening stream $_currentUrl (cam=$_activeCamera)');
        await _frontPlayer!.open(Media(_currentUrl), play: true);
      }

      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() { _streaming = true; _connecting = false; });
      }
    } catch (e) {
      debugPrint('DashcamLiveView: stream error: $e');
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Failed to connect to stream.\n'
              'URL: $_currentUrl\n'
              'Try a different URL.';
        });
      }
    }
  }

  void _stopStream() {
    _frontPlayer?.dispose();
    _frontPlayer = null;
    _frontController = null;
    _backPlayer?.dispose();
    _backPlayer = null;
    _backController = null;
    if (mounted) setState(() { _streaming = false; _connecting = false; });
  }

  @override
  Widget build(BuildContext context) {
    final dcState = ref.watch(dashcamProvider);

    // Single RTSP URL from API
    final streamUrl = dcState.mediaInfo?.rtsp.isNotEmpty == true
        ? '${dcState.mediaInfo!.rtsp}:${dcState.mediaInfo!.port}'
        : DashcamService.rtspUrl;

    return Column(children: [
      // ── Top bar: URL selector + layout toggle + controls ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(children: [
          // Layout toggle
          _ToggleBtn(
            icon: Icons.view_sidebar_rounded,
            label: _sideBySide ? 'Side-by-Side' : 'Single',
            active: _sideBySide,
            onTap: () {
              if (_streaming) _stopStream();
              setState(() => _sideBySide = !_sideBySide);
            },
          ),
          const SizedBox(width: 8),
          // Camera selector (single view only)
          if (!_sideBySide) ...[
            _ToggleBtn(
              icon: Icons.videocam_rounded,
              label: _activeCamera == 0 ? 'Front' : 'Back',
              active: true,
              onTap: () {
                if (_streaming) _stopStream();
                setState(() => _activeCamera = _activeCamera == 0 ? 1 : 0);
              },
            ),
            const SizedBox(width: 8),
          ],
          // Stream URL display
          Expanded(
            child: Text(streamUrl,
              style: const TextStyle(color: Colors.white38, fontSize: 11,
                  fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          if (_streaming)
            _CtrlBtn(Icons.stop_rounded, 'Stop', Colors.redAccent, _stopStream)
          else
            _CtrlBtn(
              Icons.play_arrow_rounded, 'Start',
              const Color(0xFF4FC3F7),
              _connecting ? null : _startStream,
            ),
        ]),
      ),

      // ── Video area ──
      Expanded(
        child: _streaming
            ? _sideBySide
                ? _buildSideBySide()
                : _buildSingleView()
            : _connecting
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 32, height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: Color(0xFF4FC3F7))),
                      SizedBox(height: 12),
                      Text('Connecting to live stream...',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ]),
                  )
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.live_tv_rounded, color: Colors.white12, size: 48),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12))
                      else
                        const Text('Click Start to view live feed',
                            style: TextStyle(color: Colors.white30, fontSize: 13)),
                      const SizedBox(height: 8),
                      Text(
                        _sideBySide ? 'Side-by-Side mode (Front + Back)' : 'Single camera mode',
                        style: const TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ]),
                  ),
      ),

      // ── Bottom controls ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _CtrlBtn(
            dcState.isRecording
                ? Icons.stop_circle_rounded
                : Icons.fiber_manual_record_rounded,
            dcState.isRecording ? 'Stop Rec' : 'Record',
            dcState.isRecording ? Colors.redAccent : Colors.red,
            () async {
              final notifier = ref.read(dashcamProvider.notifier);
              dcState.isRecording
                  ? await notifier.stopRecording()
                  : await notifier.startRecording();
            },
          ),
          if (dcState.recDuration > 0) ...[
            const SizedBox(width: 8),
            Text(
              '${(dcState.recDuration ~/ 60).toString().padLeft(2, '0')}:'
              '${(dcState.recDuration % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12,
                  fontFamily: 'monospace'),
            ),
          ],
          const SizedBox(width: 16),
          _CtrlBtn(Icons.camera_alt_rounded, 'Snapshot', Colors.white60,
            () => DashcamService.takeSnapshot()),
          const SizedBox(width: 16),
          _CtrlBtn(Icons.refresh_rounded, 'Refresh', Colors.white60,
            () => ref.read(dashcamProvider.notifier).refreshFiles()),
        ]),
      ),
    ]);
  }

  Widget _buildSideBySide() {
    return Row(children: [
      // Front camera
      Expanded(
        child: _buildVideoPanel(
          'Front',
          _frontController,
          Colors.cyan,
        ),
      ),
      const VerticalDivider(width: 2, color: Colors.white10),
      // Back camera
      Expanded(
        child: _buildVideoPanel(
          'Back',
          _backController,
          Colors.orange,
        ),
      ),
    ]);
  }

  Widget _buildSingleView() {
    return _buildVideoPanel(
      _activeCamera == 0 ? 'Front' : 'Back',
      _frontController,
      _activeCamera == 0 ? Colors.cyan : Colors.orange,
    );
  }

  Widget _buildVideoPanel(String label, VideoController? controller, Color color) {
    return Stack(
      children: [
        Container(
          color: Colors.black,
          child: controller != null
              ? Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                )
              : const Center(
                  child: Icon(Icons.videocam_off_rounded,
                      color: Colors.white12, size: 32)),
        ),
        // Camera label badge
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _CtrlBtn(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: onTap != null
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: onTap != null
              ? color.withValues(alpha: 0.3)
              : Colors.white10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: onTap != null ? color : Colors.white24, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
              color: onTap != null ? color : Colors.white24, fontSize: 10)),
        ]),
      ),
    ),
  );
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn({required this.icon, required this.label,
      required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF4FC3F7).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active
            ? const Color(0xFF4FC3F7).withValues(alpha: 0.4)
            : Colors.white10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: active
            ? const Color(0xFF4FC3F7) : Colors.white38),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: active
            ? const Color(0xFF4FC3F7) : Colors.white38)),
      ]),
    ),
  );
}
