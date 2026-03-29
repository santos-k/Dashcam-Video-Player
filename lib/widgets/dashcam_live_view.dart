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
  Player? _player;
  VideoController? _controller;
  bool _streaming = false;
  bool _connecting = false;
  String? _error;
  late String _currentUrl = DashcamService.rtspFrontUrl;

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  Future<void> _startStream() async {
    if (_connecting) return;
    setState(() { _connecting = true; _error = null; });

    // Switch dashcam to video mode for live stream
    try {
      await DashcamService.setMode(0);
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {}

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 0,
      ),
    );

    _controller = VideoController(_player!);

    try {
      await _player!.open(Media(_currentUrl), play: true);
      // Wait a moment to see if it actually connects
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() { _streaming = true; _connecting = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Failed to connect to RTSP stream.\nTry a different URL.';
        });
      }
    }
  }

  void _stopStream() {
    _player?.dispose();
    _player = null;
    _controller = null;
    if (mounted) setState(() { _streaming = false; _connecting = false; });
  }

  @override
  Widget build(BuildContext context) {
    final dcState = ref.watch(dashcamProvider);

    return Column(children: [
      // Stream URL selector + controls
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(children: [
          const Icon(Icons.videocam_rounded, color: Colors.white30, size: 16),
          const SizedBox(width: 8),
          // URL selector
          Expanded(
            child: DropdownButton<String>(
              value: DashcamService.rtspUrls.contains(_currentUrl)
                  ? _currentUrl : DashcamService.rtspUrls.first,
              dropdownColor: const Color(0xFF222222),
              style: const TextStyle(color: Colors.white60, fontSize: 11,
                  fontFamily: 'monospace'),
              underline: const SizedBox(),
              isExpanded: true,
              items: [
                for (final url in DashcamService.rtspUrls)
                  DropdownMenuItem(value: url,
                    child: Text(url, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _currentUrl = v);
                if (_streaming) {
                  _stopStream();
                  _startStream();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          if (_streaming)
            _CtrlBtn(Icons.stop_rounded, 'Stop', Colors.redAccent, _stopStream)
          else
            _CtrlBtn(
              Icons.play_arrow_rounded, 'Start Stream',
              const Color(0xFF4FC3F7),
              _connecting ? null : _startStream,
            ),
        ]),
      ),

      // Video area
      Expanded(
        child: _streaming && _controller != null
            ? Container(
                color: Colors.black,
                child: Video(
                  controller: _controller!,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              )
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
                        const Text('Click Start Stream to view live feed',
                            style: TextStyle(color: Colors.white30, fontSize: 13)),
                    ]),
                  ),
      ),

      // Camera controls bar
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
            dcState.isRecording ? 'Stop Recording' : 'Record',
            dcState.isRecording ? Colors.redAccent : Colors.red,
            () async {
              final notifier = ref.read(dashcamProvider.notifier);
              dcState.isRecording
                  ? await notifier.stopRecording()
                  : await notifier.startRecording();
            },
          ),
          const SizedBox(width: 16),
          _CtrlBtn(Icons.camera_alt_rounded, 'Photo', Colors.white60,
            () => ref.read(dashcamProvider.notifier).takePhoto()),
          const SizedBox(width: 16),
          _CtrlBtn(Icons.refresh_rounded, 'Refresh Files', Colors.white60,
            () => ref.read(dashcamProvider.notifier).refreshFiles()),
        ]),
      ),
    ]);
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Icon(icon, color: onTap != null ? color : Colors.white24, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: onTap != null ? color : Colors.white24, fontSize: 11)),
        ]),
      ),
    ),
  );
}
