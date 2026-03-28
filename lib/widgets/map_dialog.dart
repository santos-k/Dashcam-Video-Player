// lib/widgets/map_dialog.dart
//
// Shows GPS coordinates for the current clip in a sidebar (endDrawer) with
// an embedded OpenStreetMap tile preview.  Defaults to India when no GPS
// data is available.  The user can open the location in a browser.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/export_service.dart';

// Default: centre of India
const double _defaultLat = 20.5937;
const double _defaultLon = 78.9629;
const int    _defaultZoom = 5;
const int    _coordZoom   = 15;

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
  bool _hasCoords = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath != null) {
      _tryExtractGPS();
    }
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

  double? get _lat => double.tryParse(_latCtrl.text.trim());
  double? get _lon => double.tryParse(_lonCtrl.text.trim());

  Future<void> _tryExtractGPS() async {
    setState(() { _loading = true; _error = null; });
    final coords = await ExportService.extractGPS(widget.videoPath!);
    if (!mounted) return;
    if (coords != null) {
      _latCtrl.text = coords.$1.toStringAsFixed(6);
      _lonCtrl.text = coords.$2.toStringAsFixed(6);
      _hasCoords = true;
    } else {
      _error = 'No GPS data found. Showing India by default.';
      _hasCoords = false;
    }
    setState(() => _loading = false);
  }

  Future<void> _openOSM() async {
    final lat = _lat ?? _defaultLat;
    final lon = _lon ?? _defaultLon;
    final z   = _hasCoords ? _coordZoom : _defaultZoom;
    final uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=$z/$lat/$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openGoogleMaps() async {
    final lat = _lat ?? _defaultLat;
    final lon = _lon ?? _defaultLon;
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat  = _lat ?? _defaultLat;
    final lon  = _lon ?? _defaultLon;
    final zoom = _hasCoords ? _coordZoom : _defaultZoom;

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      width: 340,
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

            // Map preview
            _OsmTileGrid(lat: lat, lon: lon, zoom: zoom),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
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
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_error!,
                            style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ),

                      const Text('Latitude',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      _CoordField(hint: 'e.g. 20.5937', controller: _latCtrl,
                        onChanged: (_) => setState(() {
                          _hasCoords = _lat != null && _lon != null;
                        }),
                      ),

                      const SizedBox(height: 12),

                      const Text('Longitude',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      _CoordField(hint: 'e.g. 78.9629', controller: _lonCtrl,
                        onChanged: (_) => setState(() {
                          _hasCoords = _lat != null && _lon != null;
                        }),
                      ),

                      const SizedBox(height: 20),

                      // Open map buttons
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _openOSM,
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

// ─── OpenStreetMap tile grid ─────────────────────────────────────────────────
//
// Renders a 3x3 grid of OSM raster tiles centered on the given coordinates.
// Each tile is 256x256; the widget shows ~768x768 logical pixels scaled to
// fit the sidebar width and a fixed height.

class _OsmTileGrid extends StatelessWidget {
  final double lat;
  final double lon;
  final int zoom;
  const _OsmTileGrid({required this.lat, required this.lon, required this.zoom});

  // Convert lat/lon to tile x/y at the given zoom level (Slippy Map convention).
  (int, int) _latlonToTile(double lat, double lon, int z) {
    final n = math.pow(2, z);
    final x = ((lon + 180) / 360 * n).floor();
    final latRad = lat * math.pi / 180;
    final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
    return (x, y);
  }

  @override
  Widget build(BuildContext context) {
    final (cx, cy) = _latlonToTile(lat, lon, zoom);

    // 3x3 grid around the center tile
    return Container(
      height: 220,
      color: const Color(0xFF1A1A1A),
      child: ClipRect(
        child: Stack(
          children: [
            // 3x3 tile grid
            for (int dy = -1; dy <= 1; dy++)
              for (int dx = -1; dx <= 1; dx++)
                Positioned(
                  left: (dx + 1) * 256.0 - 128 + 170 / 2, // center offset
                  top:  (dy + 1) * 256.0 - 128 + 110 / 2 - 128,
                  child: Image.network(
                    'https://tile.openstreetmap.org/$zoom/${cx + dx}/${cy + dy}.png',
                    width: 256,
                    height: 256,
                    fit: BoxFit.cover,
                    headers: const {
                      'User-Agent': 'DashCamPlayer/1.0',
                    },
                    errorBuilder: (_, __, ___) => Container(
                      width: 256, height: 256,
                      color: const Color(0xFF2A2A2A),
                      child: const Center(
                        child: Icon(Icons.cloud_off_rounded,
                            color: Colors.white24, size: 24)),
                    ),
                  ),
                ),

            // Center pin marker
            const Center(
              child: Icon(Icons.location_on,
                  color: Colors.red, size: 32),
            ),

            // Gradient overlay at bottom for visual blend
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                height: 30,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xFF121212)],
                  ),
                ),
              ),
            ),

            // OSM attribution
            Positioned(
              right: 4, bottom: 2,
              child: Text('\u00A9 OpenStreetMap',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 8)),
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
  final ValueChanged<String>? onChanged;
  const _CoordField({
    required this.hint,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  controller,
      onChanged:   onChanged,
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
