// lib/widgets/map_dialog.dart
//
// Shows GPS coordinates for the current clip and lets the user open them
// in the system browser on OpenStreetMap.  GPS is extracted from video
// metadata automatically when ffprobe is available.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/export_service.dart';

Future<void> showMapDialog(BuildContext context, String? videoPath) {
  return showDialog(
    context: context,
    builder: (_) => _MapDialog(videoPath: videoPath),
  );
}

class _MapDialog extends StatefulWidget {
  final String? videoPath;
  const _MapDialog({this.videoPath});

  @override
  State<_MapDialog> createState() => _MapDialogState();
}

class _MapDialogState extends State<_MapDialog> {
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  bool _loading  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath != null) _tryExtractGPS();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryExtractGPS() async {
    setState(() { _loading = true; _error = null; });
    final coords = await ExportService.extractGPS(widget.videoPath!);
    if (!mounted) return;
    if (coords != null) {
      _latCtrl.text = coords.$1.toStringAsFixed(6);
      _lonCtrl.text = coords.$2.toStringAsFixed(6);
    } else {
      _error = 'No GPS data found in video metadata.\nEnter coordinates manually.';
    }
    setState(() => _loading = false);
  }

  Future<void> _openMap() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null || lon == null) {
      setState(() => _error = 'Enter valid latitude and longitude.');
      return;
    }
    final uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=15/$lat/$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openGoogleMaps() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null || lon == null) {
      setState(() => _error = 'Enter valid latitude and longitude.');
      return;
    }
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor:  const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(children: [
        const Icon(Icons.map_rounded, color: Color(0xFF4FC3F7), size: 20),
        const SizedBox(width: 8),
        const Text('Map',
          style: TextStyle(color: Colors.white70, fontSize: 16,
              fontWeight: FontWeight.w600)),
        const Spacer(),
        if (widget.videoPath != null)
          Tooltip(
            message: 'Re-extract GPS from video',
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Colors.white38, size: 18),
              onPressed: _loading ? null : _tryExtractGPS,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
      ]),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4FC3F7))),
                SizedBox(width: 10),
                Text('Extracting GPS…',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            )
          else ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center),
              ),
            _CoordField(
              label:      'Latitude',
              hint:       'e.g. 51.5074',
              controller: _latCtrl,
            ),
            const SizedBox(height: 10),
            _CoordField(
              label:      'Longitude',
              hint:       'e.g. -0.1278',
              controller: _lonCtrl,
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
            style: TextStyle(color: Colors.white38)),
        ),
        _MapActionBtn(
          icon:    Icons.public_rounded,
          label:   'OpenStreetMap',
          onTap:   _openMap,
          enabled: !_loading,
        ),
        _MapActionBtn(
          icon:    Icons.map_outlined,
          label:   'Google Maps',
          onTap:   _openGoogleMaps,
          enabled: !_loading,
        ),
      ],
    );
  }
}

// ─── Coordinate text field ────────────────────────────────────────────────────

class _CoordField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  const _CoordField({
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  controller,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-+]')),
      ],
      style: const TextStyle(color: Colors.white70, fontSize: 13),
      decoration: InputDecoration(
        labelText:    label,
        hintText:     hint,
        labelStyle:   const TextStyle(color: Colors.white38, fontSize: 12),
        hintStyle:    const TextStyle(color: Colors.white24, fontSize: 12),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4FC3F7))),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
      ),
    );
  }
}

// ─── Map open button ──────────────────────────────────────────────────────────

class _MapActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final bool     enabled;
  const _MapActionBtn({
    required this.icon, required this.label,
    required this.onTap, required this.enabled,
  });

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: enabled ? onTap : null,
    icon:  Icon(icon, size: 14),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    style: ElevatedButton.styleFrom(
      backgroundColor:    const Color(0xFF4FC3F7),
      foregroundColor:    Colors.black,
      disabledBackgroundColor: Colors.white12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );
}
