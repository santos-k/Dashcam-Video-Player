// lib/widgets/dashcam_overlay.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashcam_state.dart';
import '../providers/dashcam_providers.dart';
import '../services/dashcam_service.dart';
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
                      const _SettingsTab(),
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
            if (device!.camnum > 1) ...[
              const SizedBox(width: 6),
              _pill('${device!.camnum} cam', const Color(0xFF4FC3F7)),
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
                  hintText: '192.168.169.1',
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
        _Step('2', 'Connect your PC to the dashcam Wi-Fi hotspot (e.g. onelap-5Ghz-…)'),
        _Step('3', 'Click Connect — default IP is 192.168.169.1'),
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

/// Settings labels and icons for known dashcam params.
const _paramMeta = <String, (IconData, String)>{
  'switchcam':             (Icons.cameraswitch_rounded,       'Camera View'),
  'mic':                   (Icons.mic_rounded,                'Microphone'),
  'osd':                   (Icons.subtitles_rounded,          'On-Screen Display'),
  'rec_resolution':        (Icons.high_quality_rounded,       'Resolution'),
  'rec_split_duration':    (Icons.timelapse_rounded,          'Clip Duration'),
  'speaker':               (Icons.volume_up_rounded,          'Speaker Volume'),
  'gsr_sensitivity':       (Icons.vibration_rounded,          'G-Sensor Sensitivity'),
  'park_gsr_sensitivity':  (Icons.local_parking_rounded,      'Park G-Sensor'),
  'timelapse_rate':        (Icons.speed_rounded,              'Timelapse Rate'),
  'boot_sound':            (Icons.music_note_rounded,         'Boot Sound'),
  'speed_unit':            (Icons.speed_rounded,              'Speed Unit'),
  'rec':                   (Icons.fiber_manual_record_rounded,'Recording'),
};

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dcState = ref.watch(dashcamProvider);
    final notifier = ref.read(dashcamProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Camera Control ──
        const _SectionTitle('Camera Control'),
        _SettingRow(
          icon: Icons.fiber_manual_record_rounded,
          label: dcState.isRecording ? 'Recording…' : 'Start Recording',
          trailing: ElevatedButton(
            onPressed: () => dcState.isRecording
                ? notifier.stopRecording()
                : notifier.startRecording(),
            style: ElevatedButton.styleFrom(
              backgroundColor: dcState.isRecording ? Colors.grey : Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: Text(dcState.isRecording ? 'STOP' : 'REC',
                style: const TextStyle(fontSize: 11)),
          ),
        ),
        if (dcState.deviceInfo != null && dcState.deviceInfo!.camnum > 1) ...[
          _SettingRow(
            icon: Icons.cameraswitch_rounded,
            label: 'Switch Camera',
            subtitle: 'Current: ${dcState.deviceInfo!.curcamid == 0 ? "Front" : "Back"}',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _ActionBtn('Front', () => notifier.switchCamera(0)),
              const SizedBox(width: 4),
              _ActionBtn('Back', () => notifier.switchCamera(1)),
            ]),
          ),
        ],

        const SizedBox(height: 12),
        const _SectionTitle('Dashcam Settings'),

        // ── Dynamic settings from API ──
        // Filter out 'switchcam' and 'rec' (handled above)
        for (final schema in dcState.paramSchemas)
          if (schema.name != 'switchcam' && schema.name != 'rec')
            _DynamicSetting(
              schema: schema,
              currentValue: dcState.paramValue(schema.name) ?? 0,
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
          icon: Icons.refresh_rounded,
          label: 'Refresh settings',
          trailing: _ActionBtn('Refresh', () => notifier.refreshSettings()),
        ),

        // Storage info
        if (dcState.storageInfo != null) ...[
          const SizedBox(height: 12),
          const _SectionTitle('Storage'),
          _SettingRow(
            icon: Icons.sd_card_rounded,
            label: 'SD Card',
            subtitle: '${dcState.storageInfo!.usedDisplay} used of ${dcState.storageInfo!.totalDisplay}'
                ' (${dcState.storageInfo!.freeDisplay} free)',
            trailing: const SizedBox(),
          ),
        ],

        // Device info
        if (dcState.deviceInfo != null) ...[
          const SizedBox(height: 12),
          const _SectionTitle('Device Info'),
          _InfoRow('SSID', dcState.deviceInfo!.ssid),
          _InfoRow('UUID', dcState.deviceInfo!.uuid),
          _InfoRow('Software', dcState.deviceInfo!.softver),
          _InfoRow('Hardware', dcState.deviceInfo!.hwver),
          _InfoRow('Cameras', '${dcState.deviceInfo!.camnum}'),
        ],
      ],
    );
  }
}

/// Dynamic setting row — built from the param schema.
class _DynamicSetting extends ConsumerWidget {
  final DashcamParamSchema schema;
  final int currentValue;

  const _DynamicSetting({
    required this.schema,
    required this.currentValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = _paramMeta[schema.name];
    final icon = meta?.$1 ?? Icons.tune_rounded;
    final label = meta?.$2 ?? _prettifyName(schema.name);

    // For binary on/off params, use a switch
    if (schema.items.length == 2 &&
        schema.items[0].toLowerCase() == 'off' &&
        schema.items[1].toLowerCase() == 'on') {
      return _SettingRow(
        icon: icon,
        label: label,
        trailing: Switch(
          value: currentValue == schema.index[1],
          activeColor: const Color(0xFF4FC3F7),
          onChanged: (v) {
            final newVal = v ? schema.index[1] : schema.index[0];
            ref.read(dashcamProvider.notifier).setParam(schema.name, newVal);
          },
        ),
      );
    }

    // For multi-option params, use a dropdown
    return _SettingRow(
      icon: icon,
      label: label,
      trailing: DropdownButton<int>(
        value: schema.index.contains(currentValue)
            ? currentValue
            : (schema.index.isNotEmpty ? schema.index.first : 0),
        dropdownColor: const Color(0xFF222222),
        style: const TextStyle(color: Colors.white60, fontSize: 11),
        underline: const SizedBox(),
        items: [
          for (int i = 0; i < schema.items.length && i < schema.index.length; i++)
            DropdownMenuItem(
              value: schema.index[i],
              child: Text(schema.items[i]),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          ref.read(dashcamProvider.notifier).setParam(schema.name, v);
        },
      ),
    );
  }

  static String _prettifyName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      const SizedBox(width: 26),
      SizedBox(
        width: 80,
        child: Text(label,
            style: const TextStyle(color: Colors.white30, fontSize: 11)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(color: Colors.white54, fontSize: 11,
                fontFamily: 'monospace')),
      ),
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
