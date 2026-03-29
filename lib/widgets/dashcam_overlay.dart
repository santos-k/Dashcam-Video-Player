// lib/widgets/dashcam_overlay.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashcam_state.dart';
import '../providers/dashcam_providers.dart';
import '../services/dashcam_service.dart';
import '../services/dashcam_tcp_service.dart';
import 'dashcam_file_browser.dart';
import 'dashcam_live_view.dart';

class DashcamOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const DashcamOverlay({super.key, required this.onClose});

  @override
  ConsumerState<DashcamOverlay> createState() => _DashcamOverlayState();
}

class _DashcamOverlayState extends ConsumerState<DashcamOverlay>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dcState = ref.watch(dashcamProvider);
    final connected = dcState.status == DashcamConnectionStatus.connected;
    final size = MediaQuery.of(context).size;

    return Center(
      child: Container(
        width:  (size.width  * 0.92).clamp(400, 1200),
        height: (size.height * 0.90).clamp(300, 850),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 32, offset: const Offset(0, 12)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // ── Header with connection status ──
          _Header(
            status:    dcState.status,
            error:     dcState.errorMessage,
            device:    dcState.deviceInfo,
            storage:   dcState.storageInfo,
            onConnect: () => ref.read(dashcamProvider.notifier).connect(),
            onDisconnect: () => ref.read(dashcamProvider.notifier).disconnect(),
            onClose:   widget.onClose,
          ),

          // ── Tab bar ──
          Container(
            color: const Color(0xFF1A1A1A),
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: const Color(0xFF4FC3F7),
              labelColor: const Color(0xFF4FC3F7),
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(icon: Icon(Icons.folder_rounded, size: 16), text: 'Files'),
                Tab(icon: Icon(Icons.videocam_rounded, size: 16), text: 'Live View'),
                Tab(icon: Icon(Icons.settings_rounded, size: 16), text: 'Settings'),
              ],
            ),
          ),

          // ── Tab content ──
          Expanded(
            child: connected
                ? TabBarView(
                    controller: _tabCtrl,
                    children: [
                      DashcamFileBrowser(files: dcState.files),
                      const DashcamLiveView(),
                      _SettingsTab(storage: dcState.storageInfo),
                    ],
                  )
                : _DisconnectedBody(status: dcState.status, error: dcState.errorMessage),
          ),
        ]),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final DashcamConnectionStatus status;
  final String? error;
  final DashcamDeviceInfo? device;
  final DashcamStorageInfo? storage;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onClose;

  const _Header({
    required this.status,
    this.error,
    this.device,
    this.storage,
    required this.onConnect,
    required this.onDisconnect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final (dotColor, label) = switch (status) {
      DashcamConnectionStatus.disconnected => (Colors.white30, 'Not connected'),
      DashcamConnectionStatus.connecting   => (Colors.amber,   'Connecting...'),
      DashcamConnectionStatus.connected    => (Colors.green,   'Connected'),
      DashcamConnectionStatus.error        => (Colors.red,     'Error'),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(children: [
        const Icon(Icons.wifi_rounded, color: Color(0xFF4FC3F7), size: 20),
        const SizedBox(width: 10),
        // Status dot + label
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: dotColor, fontSize: 12)),
        const SizedBox(width: 10),

        // Device info + IP
        if (status == DashcamConnectionStatus.connected) ...[
          Text(DashcamService.ip,
              style: const TextStyle(color: Colors.white38, fontSize: 10,
                  fontFamily: 'monospace')),
          if (device != null) ...[
            const SizedBox(width: 8),
            Text(device!.model,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            if (device!.firmware.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text('v${device!.firmware}',
                  style: const TextStyle(color: Colors.white30, fontSize: 10)),
            ],
          ],
        ],

        const Spacer(),

        // Storage bar
        if (storage != null && status == DashcamConnectionStatus.connected)
          _StorageChip(storage: storage!),

        const SizedBox(width: 8),

        // Connect / Disconnect button
        if (status == DashcamConnectionStatus.connected)
          TextButton(
            onPressed: onDisconnect,
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          )
        else if (status != DashcamConnectionStatus.connecting)
          ElevatedButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.wifi_rounded, size: 14),
            label: const Text('Connect', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4FC3F7),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),

        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
          onPressed: onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}

class _StorageChip extends StatelessWidget {
  final DashcamStorageInfo storage;
  const _StorageChip({required this.storage});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${storage.usedDisplay} used / ${storage.totalDisplay} total',
      child: Container(
        width: 100, height: 16,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(children: [
          FractionallySizedBox(
            widthFactor: storage.usedPercent.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                color: storage.usedPercent > 0.9
                    ? Colors.red.withValues(alpha: 0.6)
                    : const Color(0xFF4FC3F7).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Center(
            child: Text('${storage.freeDisplay} free',
                style: const TextStyle(color: Colors.white54, fontSize: 8)),
          ),
        ]),
      ),
    );
  }
}

// ─── Disconnected body ──────────────────────────────────────────────────────

class _DisconnectedBody extends ConsumerStatefulWidget {
  final DashcamConnectionStatus status;
  final String? error;
  const _DisconnectedBody({required this.status, this.error});

  @override
  ConsumerState<_DisconnectedBody> createState() => _DisconnectedBodyState();
}

class _DisconnectedBodyState extends ConsumerState<_DisconnectedBody> {
  late final TextEditingController _ipCtrl;

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: DashcamService.ip);
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          widget.status == DashcamConnectionStatus.error
              ? Icons.wifi_off_rounded
              : Icons.wifi_rounded,
          color: widget.status == DashcamConnectionStatus.error
              ? Colors.redAccent
              : Colors.white12,
          size: 48,
        ),
        const SizedBox(height: 16),
        if (widget.status == DashcamConnectionStatus.connecting) ...[
          const SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7))),
          const SizedBox(height: 12),
          const Text('Connecting to dashcam...',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ] else ...[
          Text(
            widget.error ?? 'Connect to your dashcam Wi-Fi network,\nthen click Connect.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.status == DashcamConnectionStatus.error
                  ? Colors.redAccent
                  : Colors.white38,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Editable IP field
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Row(children: [
            const Text('Dashcam IP:',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                style: const TextStyle(color: Colors.white70, fontSize: 13,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  hintText: '192.168.1.254',
                  hintStyle: const TextStyle(color: Colors.white24),
                ),
                onChanged: (v) {
                  ref.read(dashcamProvider.notifier).setIp(v.trim());
                },
                onSubmitted: (_) {
                  ref.read(dashcamProvider.notifier).connect();
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: widget.status == DashcamConnectionStatus.connecting
                  ? null
                  : () => ref.read(dashcamProvider.notifier).connect(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: const Text('Connect', style: TextStyle(fontSize: 11)),
            ),
          ]),
        ),

        const SizedBox(height: 20),
        _HelpCard(),
      ]),
    );
  }
}

class _HelpCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('HOW TO CONNECT',
            style: TextStyle(color: Colors.white24, fontSize: 10,
                fontWeight: FontWeight.w600, letterSpacing: 1)),
        SizedBox(height: 10),
        _Step('1', 'Turn on your Onelap dashcam and enable its Wi-Fi'),
        _Step('2', 'Connect your PC to the dashcam Wi-Fi hotspot'),
        _Step('3', 'Click Connect — it auto-scans common IPs'),
        _Step('4', 'If auto-scan fails, enter the IP manually'),
        SizedBox(height: 12),
        Text('FIND DASHCAM IP FROM PHONE',
            style: TextStyle(color: Colors.white24, fontSize: 10,
                fontWeight: FontWeight.w600, letterSpacing: 1)),
        SizedBox(height: 8),
        Text(
          'iOS: Settings → Wi-Fi → tap (i) next to dashcam network → Router IP\n'
          'Android: Settings → Wi-Fi → tap connected network → Gateway',
          style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step(this.num, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(num,
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 10,
                  fontWeight: FontWeight.w600))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: const TextStyle(color: Colors.white38, fontSize: 12))),
      ]),
    );
  }
}

// ─── Settings tab ───────────────────────────────────────────────────────────

class _SettingsTab extends ConsumerWidget {
  final DashcamStorageInfo? storage;
  const _SettingsTab({this.storage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(dashcamProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('Camera Control'),
        _SettingRow(
          icon: Icons.fiber_manual_record_rounded,
          label: 'Start Recording',
          trailing: ElevatedButton(
            onPressed: () => notifier.startRecording(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('REC', style: TextStyle(fontSize: 11)),
          ),
        ),
        _SettingRow(
          icon: Icons.stop_rounded,
          label: 'Stop Recording',
          trailing: _ActionBtn('Stop', () => notifier.stopRecording()),
        ),
        _SettingRow(
          icon: Icons.camera_alt_rounded,
          label: 'Take Photo',
          trailing: _ActionBtn('Capture', () => notifier.takePhoto()),
        ),

        const SizedBox(height: 12),
        const _SectionTitle('Video Settings'),
        _DropdownSetting(
          icon: Icons.high_quality_rounded,
          label: 'Resolution',
          items: const {'1080p 30fps': 0, '1080p 60fps': 1, '720p 30fps': 2, '720p 60fps': 3},
          onChanged: (v) => DashcamService.setSetting(2002, v),
        ),
        _DropdownSetting(
          icon: Icons.loop_rounded,
          label: 'Loop Recording',
          items: const {'Off': 0, '1 min': 1, '3 min': 2, '5 min': 3},
          onChanged: (v) => DashcamService.setSetting(2003, v),
        ),
        _ToggleSetting(
          icon: Icons.hdr_on_rounded,
          label: 'WDR / HDR',
          cmd: 2004,
        ),
        _ToggleSetting(
          icon: Icons.mic_rounded,
          label: 'Audio Recording',
          cmd: 2007,
        ),
        _ToggleSetting(
          icon: Icons.date_range_rounded,
          label: 'Date Stamp',
          cmd: 2008,
        ),
        _ToggleSetting(
          icon: Icons.directions_car_rounded,
          label: 'Motion Detection',
          cmd: 2006,
        ),
        _DropdownSetting(
          icon: Icons.vibration_rounded,
          label: 'G-Sensor Sensitivity',
          items: const {'Off': 0, 'Low': 1, 'Medium': 2, 'High': 3},
          onChanged: (v) => DashcamService.setSetting(2011, v),
        ),

        const SizedBox(height: 12),
        const _SectionTitle('Device'),
        _SettingRow(
          icon: Icons.access_time_rounded,
          label: 'Sync date/time to PC',
          trailing: _ActionBtn('Sync', () => notifier.syncDateTime()),
        ),
        _SettingRow(
          icon: Icons.refresh_rounded,
          label: 'Refresh file list',
          trailing: _ActionBtn('Refresh', () => notifier.refreshFiles()),
        ),
        _SettingRow(
          icon: Icons.bug_report_rounded,
          label: 'Probe API (debug)',
          trailing: _ActionBtn('Probe', () async {
            final results = <String>[];
            final base = DashcamService.baseUrl;
            // Comprehensive probe: CGI, REST, CARDV, iCatch, Ambarella, etc.
            for (final path in [
              '/',
              '/?custom=1&cmd=3015',
              '/?custom=1&cmd=3012',
              // iCatch / Config.cgi style
              '/cgi-bin/Config.cgi?action=get&property=Camera.Menu.Net.WIFI.AP.SSID',
              '/cgi-bin/Config.cgi?action=get_file_list',
              '/cgi-bin/Config.cgi?action=get&property=Camera.Preview.MJPEG.status',
              '/cgi-bin/cmd.cgi?cmd=getfilelist',
              // REST / JSON API
              '/api/v1/files',
              '/api/v1/status',
              '/api/files',
              '/api/config',
              '/v1/files',
              // Common dashcam paths
              '/CARDV/',
              '/CARDV/DCIM/',
              '/tmp/SD0/',
              '/tmp/SD0/DCIM/',
              '/tmp/fuse_d/',
              '/tmp/fuse_d/DCIM/',
              '/tmp/FL0/',
              '/tmp/FL0/DCIM/',
              // MJPEG/stream paths
              '/livestream',
              '/live',
              '/stream',
              '/mjpeg',
              '/video',
              '/preview',
            ]) {
              try {
                final body = await DashcamService.fetchRaw(
                    '${DashcamService.baseUrl}$path');
                results.add('$path → ${body.length}B: ${body.substring(0, body.length.clamp(0, 200))}');
              } catch (e) {
                results.add('$path → ERROR: $e');
              }
            }
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('API Probe Results',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  content: SizedBox(
                    width: 500, height: 400,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        results.join('\n\n'),
                        style: const TextStyle(color: Colors.white60,
                            fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('Close')),
                  ],
                ),
              );
            }
          }),
        ),
        _SettingRow(
          icon: Icons.bug_report_rounded,
          label: 'Deep scan (ports + POST + formats)',
          trailing: _ActionBtn('Scan', () async {
            final results = <String>[];
            final ip = DashcamService.ip;

            // 1. TCP port scan
            results.add('=== TCP PORT SCAN ===');
            for (final port in [80, 554, 3333, 7878, 8080, 8192, 8554, 9999, 6666, 4321, 5000, 8000, 443]) {
              try {
                final sock = await Socket.connect(ip, port,
                    timeout: const Duration(seconds: 2));
                results.add('TCP:$port → OPEN');
                sock.destroy();
              } catch (_) {
                results.add('TCP:$port → closed');
              }
            }

            // 2. HTTP on open ports
            results.add('\n=== HTTP PROBES ===');
            for (final port in [80, 5000, 3333, 7878, 8080, 8192]) {
              try {
                final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
                final req = await client.getUrl(Uri.parse('http://$ip:$port/'));
                final res = await req.close().timeout(const Duration(seconds: 3));
                final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
                results.add('HTTP:$port/ → [${res.statusCode}] ${body.substring(0, body.length.clamp(0, 120))}');
                client.close(force: true);
              } catch (e) {
                results.add('HTTP:$port/ → $e'.substring(0, 80));
              }
            }

            // 3. Try POST requests on port 80
            results.add('\n=== POST REQUESTS ===');
            for (final entry in {
              '/': '{"cmd":"list_files"}',
              '/cmd': '{"cmd":"list_files"}',
              '/': '{"action":"get_file_list"}',
              '/rpc': '{"method":"get_file_list","id":1}',
              '/?cmd=3015': '',
              '/?cmd=list': '',
              '/?action=list_files': '',
            }.entries) {
              try {
                final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
                final req = await client.postUrl(Uri.parse('http://$ip${entry.key}'));
                req.headers.contentType = ContentType.json;
                if (entry.value.isNotEmpty) req.write(entry.value);
                final res = await req.close().timeout(const Duration(seconds: 3));
                final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
                results.add('POST ${entry.key} → [${res.statusCode}] ${body.substring(0, body.length.clamp(0, 120))}');
                client.close(force: true);
              } catch (e) {
                results.add('POST ${entry.key} → ERR');
              }
            }

            // 4. Try different GET query formats
            results.add('\n=== QUERY FORMATS ===');
            for (final path in [
              '/?cmd=3015',
              '/?cmd=list',
              '/?action=list',
              '/?op=list',
              '/?func=list',
              '/?cmd=get_file_list',
              '/?cmd=getfilelist',
              '/?custom=1&cmd=3015&type=0',
              '/?custom=1&cmd=3015&par=1',
              '/?custom=2&cmd=3015',
              '/onel/',
              '/onelap/',
              '/config',
              '/status',
              '/info',
              '/list',
              '/filelist',
              '/file_list',
              '/get_file_list',
              '/photo/',
              '/video/',
              '/normal/',
              '/event/',
              '/DCIM/MOVIE/',
              '/DCIM/PHOTO/',
              '/DCIM/100MEDIA/',
            ]) {
              try {
                final body = await DashcamService.fetchRaw('http://$ip$path');
                // Only show if different from defaults
                if (!body.contains('url_root success') && !body.contains('{result: 98}')) {
                  results.add('GET $path → ${body.substring(0, body.length.clamp(0, 200))}');
                }
              } catch (_) {}
            }
            results.add('(paths returning url_root/98 omitted)');

            // 5. Deep probe port 5000
            results.add('\n=== PORT 5000 DEEP PROBE ===');
            // HTTP GET on port 5000
            for (final path in [
              '/', '/status', '/config', '/files', '/list',
              '/DCIM/', '/api/', '/cmd', '/stream', '/live',
              '/?cmd=3015', '/?action=list', '/?custom=1&cmd=3015',
            ]) {
              try {
                final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
                final req = await client.getUrl(Uri.parse('http://$ip:5000$path'));
                final res = await req.close().timeout(const Duration(seconds: 3));
                final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
                results.add('GET :5000$path → [${res.statusCode}] ${body.substring(0, body.length.clamp(0, 200))}');
                client.close(force: true);
              } catch (e) {
                results.add('GET :5000$path → ${e.toString().substring(0, e.toString().length.clamp(0, 60))}');
              }
            }
            // POST on port 5000
            for (final body in [
              '{"cmd":"list_files"}',
              '{"action":"get_file_list"}',
              '{"method":"getFileList"}',
              '{"msg_id":1283}',
              '{"token":0,"msg_id":257}',
              'list_files',
            ]) {
              try {
                final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
                final req = await client.postUrl(Uri.parse('http://$ip:5000/'));
                req.headers.contentType = ContentType.json;
                req.write(body);
                final res = await req.close().timeout(const Duration(seconds: 3));
                final resp = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
                results.add('POST :5000 $body → [${res.statusCode}] ${resp.substring(0, resp.length.clamp(0, 200))}');
                client.close(force: true);
              } catch (e) {
                results.add('POST :5000 $body → ERR');
              }
            }
            // Raw TCP on port 5000
            try {
              final sock = await Socket.connect(ip, 5000, timeout: const Duration(seconds: 2));
              // Send a JSON command and read response
              sock.write('{"msg_id":257,"token":0}\n');
              await sock.flush();
              final resp = await sock.timeout(const Duration(seconds: 3)).first;
              results.add('TCP:5000 raw → ${String.fromCharCodes(resp).substring(0, String.fromCharCodes(resp).length.clamp(0, 200))}');
              sock.destroy();
            } catch (e) {
              results.add('TCP:5000 raw → $e');
            }

            if (context.mounted) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Deep Scan Results',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  content: SizedBox(
                    width: 560, height: 450,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        results.join('\n'),
                        style: const TextStyle(color: Colors.white60,
                            fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('Close')),
                  ],
                ),
              );
            }
          }),
        ),
        _SettingRow(
          icon: Icons.bug_report_rounded,
          label: 'TCP format probe (port 5000)',
          trailing: _ActionBtn('Probe TCP', () async {
            final ip = DashcamService.ip;
            final results = <String>[];

            results.add('Connecting to $ip:5000...');
            final ok = await DashcamTcpService.connect(ip);
            if (!ok) {
              results.add('FAILED to connect');
              if (context.mounted) {
                showDialog(context: context, builder: (_) => _ProbeDialog('TCP Probe', results.join('\n')));
              }
              return;
            }
            results.add('Connected!\n');

            // Drain GPS messages first
            await Future.delayed(const Duration(seconds: 1));

            final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000);
            // Try many formats: with info/time like GPS, plain, with params
            final rawCommands = <String>[
              // Same format as GPS messages (msgid + info + time)
              '{"msgid":"get_file_list","info":{},"time":$ts}',
              '{"msgid":"filelist","info":{},"time":$ts}',
              '{"msgid":"file_list","info":{},"time":$ts}',
              '{"msgid":"query_file","info":{},"time":$ts}',
              '{"msgid":"get_record_list","info":{},"time":$ts}',
              '{"msgid":"get_camera_info","info":{},"time":$ts}',
              '{"msgid":"camera_info","info":{},"time":$ts}',
              '{"msgid":"get_status","info":{},"time":$ts}',
              '{"msgid":"status","info":{},"time":$ts}',
              '{"msgid":"get_storage","info":{},"time":$ts}',
              '{"msgid":"get_setting","info":{},"time":$ts}',
              '{"msgid":"get_config","info":{},"time":$ts}',
              '{"msgid":"start_preview","info":{},"time":$ts}',
              '{"msgid":"start_stream","info":{},"time":$ts}',
              '{"msgid":"init","info":{},"time":$ts}',
              '{"msgid":"connect","info":{},"time":$ts}',
              '{"msgid":"app_connect","info":{},"time":$ts}',
              '{"msgid":"heartbeat","info":{},"time":$ts}',
              '{"msgid":"get_capability","info":{},"time":$ts}',
              '{"msgid":"get_wifi_info","info":{},"time":$ts}',
              // Without time/info
              '{"msgid":"get_file_list"}',
              '{"msgid":"get_camera_info"}',
              '{"msgid":"start_preview"}',
              // With param/token
              '{"msgid":"get_file_list","param":{"type":"all"}}',
              '{"msgid":"get_file_list","token":0}',
              '{"msg_id":257,"token":0}',
              '{"msg_id":3015}',
              // Different key names
              '{"cmd":"get_file_list"}',
              '{"type":"get_file_list"}',
              '{"action":"get_file_list"}',
            ];

            results.add('=== FORMAT PROBE (${rawCommands.length} variants) ===');
            for (final raw in rawCommands) {
              final (collected, _) = await DashcamTcpService.sendAndCollect(
                raw, collectDuration: const Duration(seconds: 1));
              // Filter out GPS noise
              final nonGps = collected.where((m) => m['msgid'] != 'gps').toList();
              if (nonGps.isNotEmpty) {
                for (final m in nonGps) {
                  final s = jsonEncode(m);
                  results.add('MATCH: $raw\n  → ${s.substring(0, s.length.clamp(0, 250))}');
                }
              }
            }

            if (!results.any((r) => r.startsWith('MATCH:'))) {
              results.add('\nNo non-GPS responses for any format.');
              results.add('Use "Stream" app on iPhone to capture Onelap app traffic.');
            }

            await DashcamTcpService.disconnect();

            if (context.mounted) {
              showDialog(context: context, builder: (_) => _ProbeDialog('TCP Format Probe', results.join('\n')));
            }
          }),
        ),
        _SettingRow(
          icon: Icons.sd_card_rounded,
          label: 'Format SD Card',
          subtitle: storage != null
              ? '${storage!.usedDisplay} used of ${storage!.totalDisplay}'
              : null,
          trailing: ElevatedButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text('Format SD Card',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  content: const Text(
                    'This will erase ALL files on the dashcam SD card.\n\nThis cannot be undone.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Format',
                            style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (ok == true) notifier.formatSD();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('Format', style: TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(text,
        style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget trailing;
  const _SettingRow({required this.icon, required this.label, this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, color: Colors.white30, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: Colors.white30, fontSize: 10)),
        ],
      )),
      trailing,
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _ActionBtn(this.label, this.onPressed);
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: Text(label, style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11)),
  );
}

class _ToggleSetting extends StatefulWidget {
  final IconData icon;
  final String label;
  final int cmd;
  const _ToggleSetting({required this.icon, required this.label, required this.cmd});

  @override
  State<_ToggleSetting> createState() => _ToggleSettingState();
}

class _ToggleSettingState extends State<_ToggleSetting> {
  bool _value = false;

  @override
  Widget build(BuildContext context) => _SettingRow(
    icon: widget.icon,
    label: widget.label,
    trailing: Switch(
      value: _value,
      activeColor: const Color(0xFF4FC3F7),
      onChanged: (v) {
        setState(() => _value = v);
        DashcamService.setSetting(widget.cmd, v ? 1 : 0);
      },
    ),
  );
}

class _DropdownSetting extends StatefulWidget {
  final IconData icon;
  final String label;
  final Map<String, int> items;
  final Future<bool> Function(int) onChanged;
  const _DropdownSetting({
    required this.icon, required this.label,
    required this.items, required this.onChanged,
  });

  @override
  State<_DropdownSetting> createState() => _DropdownSettingState();
}

class _DropdownSettingState extends State<_DropdownSetting> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.items.values.first;
  }

  @override
  Widget build(BuildContext context) => _SettingRow(
    icon: widget.icon,
    label: widget.label,
    trailing: DropdownButton<int>(
      value: _value,
      dropdownColor: const Color(0xFF222222),
      style: const TextStyle(color: Colors.white60, fontSize: 11),
      underline: const SizedBox(),
      items: [
        for (final e in widget.items.entries)
          DropdownMenuItem(value: e.value, child: Text(e.key)),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _value = v);
        widget.onChanged(v);
      },
    ),
  );
}

// ─── Reusable probe results dialog ──────────────────────────────────────────

class _ProbeDialog extends StatelessWidget {
  final String title;
  final String content;
  const _ProbeDialog(this.title, this.content);

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF1A1A1A),
    title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
    content: SizedBox(
      width: 560, height: 450,
      child: SingleChildScrollView(
        child: SelectableText(content,
          style: const TextStyle(color: Colors.white60, fontSize: 10,
              fontFamily: 'monospace')),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Close')),
    ],
  );
}
