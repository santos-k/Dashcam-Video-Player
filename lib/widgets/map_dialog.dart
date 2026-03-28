// lib/widgets/map_dialog.dart
//
// Shows GPS coordinates for the current clip in a sidebar (endDrawer) and
// lets the user open them in the system browser on OpenStreetMap or Google Maps.
// GPS is extracted from video metadata automatically when ffprobe is available.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/export_service.dart';

/// Opens the map sidebar (endDrawer) for the given video path.
void openMapSidebar(BuildContext context) {
  Scaffold.of(context).openEndDrawer();
}

class MapSidebar extends StatefulWidget {
  final String? videoPath;
  final VoidCallback? onClose;
  const MapSidebar({super.key, this.videoPath, this.onClose});

  @override
  State<MapSidebar> createState() => _MapSidebarState();
}

class _MapSidebarState extends State<MapSidebar> {
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
  void didUpdateWidget(MapSidebar old) {
    super.didUpdateWidget(old);
    if (widget.videoPath != old.videoPath && widget.videoPath != null) {
      _tryExtractGPS();
    }
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
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      width: 320,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              color: const Color(0xFF1A1A1A),
              child: Row(children: [
                const Icon(Icons.map_rounded, color: Color(0xFF4FC3F7), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('GPS / Map',
                    style: TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w600)),
                ),
                if (widget.videoPath != null)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white38, size: 18),
                    onPressed: _loading ? null : _tryExtractGPS,
                    tooltip: 'Re-extract GPS from video',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white38, size: 18),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onClose?.call();
                  },
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF4FC3F7))),
                            SizedBox(width: 10),
                            Text('Extracting GPS...',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                          ]),
                        ),
                      )
                    else ...[
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(_error!,
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                            textAlign: TextAlign.center),
                        ),

                      const Text('Latitude',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      _CoordField(
                        hint: 'e.g. 51.5074',
                        controller: _latCtrl,
                      ),

                      const SizedBox(height: 14),

                      const Text('Longitude',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      _CoordField(
                        hint: 'e.g. -0.1278',
                        controller: _lonCtrl,
                      ),

                      const SizedBox(height: 24),

                      // Open map buttons
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _openMap,
                          icon: const Icon(Icons.public_rounded, size: 16),
                          label: const Text('Open in OpenStreetMap'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4FC3F7),
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white12,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _openGoogleMaps,
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Open in Google Maps'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4FC3F7),
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white12,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Coordinate text field ────────────────────────────────────────────────────

class _CoordField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  const _CoordField({
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
        hintText:     hint,
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
