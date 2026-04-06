// lib/widgets/map_dialog.dart
//
// Inline GPS map panel that sits beside the video view.
// Syncs live marker + trail to video playback position.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import '../services/log_service.dart';

// ─── Constants ──────────────────────────────────────────────────────────────

const double _defaultLat  = 20.5937;
const double _defaultLon  = 78.9629;
const double _defaultZoom = 5;
const double _coordZoom   = 15;

const _kCyan    = Color(0xFF4FC3F7);
const _kBg      = Color(0xFF0A0A0F);
const _kSurface = Color(0xFF111118);
const _kBorder  = Color(0x1AFFFFFF);
const _kText1   = Color(0xE6FFFFFF);
const _kText3   = Color(0x4DFFFFFF);

typedef GpsPoint = (double, double, double, double, String);

// ─── Inline map panel ───────────────────────────────────────────────────────

class MapPanel extends ConsumerStatefulWidget {
  final String? videoPath;
  final VoidCallback? onClose;
  const MapPanel({super.key, this.videoPath, this.onClose});

  @override
  ConsumerState<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends ConsumerState<MapPanel> {
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _mapController = MapController();

  bool _loading   = false;
  bool _showCoords = false;
  String? _error;
  double _panelWidth = 280;

  LatLng? _marker;
  List<GpsPoint>? _gpsTrack;
  StreamSubscription? _trackSub;
  double _currentSpeed = 0;
  String _currentTime  = '';
  bool   _autoFollow   = true;

  static const _tileLayers = [
    (label: 'Standard', url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    (label: 'Topo',     url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'),
    (label: 'HOT',      url: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png'),
  ];

  @override
  void initState() {
    super.initState();
    final saved = ref.read(mapStateProvider);
    if (widget.videoPath != null) {
      _tryExtractGPS();
    } else if (saved.lat != null && saved.lon != null) {
      _latCtrl.text = saved.lat!.toStringAsFixed(6);
      _lonCtrl.text = saved.lon!.toStringAsFixed(6);
      _marker = LatLng(saved.lat!, saved.lon!);
    } else {
      _tryDeviceLocation();
    }
  }

  @override
  void didUpdateWidget(MapPanel old) {
    super.didUpdateWidget(old);
    if (widget.videoPath != old.videoPath && widget.videoPath != null) {
      _trackSub?.cancel();
      _tryExtractGPS();
    }
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _persist() {
    if (!mounted) return;
    try {
      final cam = _mapController.camera;
      ref.read(mapStateProvider.notifier).state = MapState(
        lat: _lat, lon: _lon,
        zoom: cam.zoom,
        tileLayer: ref.read(mapStateProvider).tileLayer,
      );
    } catch (_) {
      try {
        ref.read(mapStateProvider.notifier).state =
            MapState(lat: _lat, lon: _lon);
      } catch (_) {}
    }
  }

  double? get _lat => double.tryParse(_latCtrl.text.trim());
  double? get _lon => double.tryParse(_lonCtrl.text.trim());

  // ── GPS extraction ──

  Future<void> _tryExtractGPS() async {
    setState(() { _loading = true; _error = null; _gpsTrack = null; });
    _trackSub?.cancel();

    final track = await ExportService.extractGPSTrack(widget.videoPath!);
    if (!mounted) return;
    if (track != null && track.isNotEmpty) {
      _gpsTrack = track;
      final (_, lat, lon, spd, time) = track.first;
      _latCtrl.text = lat.toStringAsFixed(6);
      _lonCtrl.text = lon.toStringAsFixed(6);
      _marker = LatLng(lat, lon);
      _currentSpeed = spd;
      _currentTime = time;
      _moveToMarker(_coordZoom);
      _persist();
      appLog('Map', 'GPS track loaded: ${track.length} points');
      setState(() => _loading = false);
      _startTrackSync();
      return;
    }

    final coords = await ExportService.extractGPS(widget.videoPath!);
    if (!mounted) return;
    if (coords != null) {
      _latCtrl.text = coords.$1.toStringAsFixed(6);
      _lonCtrl.text = coords.$2.toStringAsFixed(6);
      _marker = LatLng(coords.$1, coords.$2);
      _moveToMarker(_coordZoom);
      appLog('Map', 'GPS extracted: ${coords.$1}, ${coords.$2}');
    } else {
      if (_marker == null) {
        await _tryDeviceLocation();
        if (_marker == null) _error = 'No GPS data found';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Live track sync ──

  void _startTrackSync() {
    _trackSub?.cancel();
    if (_gpsTrack == null || _gpsTrack!.isEmpty) return;

    final notifier = ref.read(playbackProvider.notifier);
    final playback = ref.read(playbackProvider);
    final player = playback.hasFront ? notifier.frontPlayer : notifier.backPlayer;

    _trackSub = player.stream.position.listen((pos) {
      if (!mounted || _gpsTrack == null) return;
      final secs = pos.inMilliseconds / 1000.0;

      GpsPoint? closest;
      double minDiff = double.infinity;
      for (final point in _gpsTrack!) {
        final diff = (point.$1 - secs).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = point;
        }
        if (diff > minDiff) break;
      }

      if (closest != null && minDiff < 2.0) {
        final (_, lat, lon, spd, time) = closest;
        final newMarker = LatLng(lat, lon);
        if (_marker == null || _marker!.latitude != lat || _marker!.longitude != lon) {
          setState(() {
            _marker = newMarker;
            _currentSpeed = spd;
            _currentTime = time;
            _latCtrl.text = lat.toStringAsFixed(6);
            _lonCtrl.text = lon.toStringAsFixed(6);
          });
          if (_autoFollow) {
            try {
              _mapController.move(newMarker, _mapController.camera.zoom);
            } catch (_) {}
          }
        }
      }
    });
  }

  // ── Device location ──

  Future<void> _tryDeviceLocation() async {
    setState(() { _loading = true; _error = null; });
    try {
      final coords = await _getDeviceLocation();
      if (!mounted) return;
      if (coords != null) {
        _latCtrl.text = coords.$1.toStringAsFixed(6);
        _lonCtrl.text = coords.$2.toStringAsFixed(6);
        _marker = LatLng(coords.$1, coords.$2);
        _moveToMarker(_coordZoom);
        _persist();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  static Future<(double, double)?> _getDeviceLocation() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
          r'''
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Devices.Geolocation.Geolocator,Windows.Foundation,ContentType=WindowsRuntime]
$a=([System.WindowsRuntimeSystemExtensions].GetMethods()|?{$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'})[0]
function W($t,$r){$m=$a.MakeGenericMethod($r);$n=$m.Invoke($null,@($t));$n.Wait(-1)|Out-Null;$n.Result}
$g=New-Object Windows.Devices.Geolocation.Geolocator
$g.DesiredAccuracy=[Windows.Devices.Geolocation.PositionAccuracy]::High
$pos=W($g.GetGeopositionAsync())([Windows.Devices.Geolocation.Geoposition])
$c=$pos.Coordinate.Point.Position
Write-Output "$($c.Latitude),$($c.Longitude)"
''',
        ]);
        if (result.exitCode == 0) {
          final parts = (result.stdout as String).trim().split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0]);
            final lon = double.tryParse(parts[1]);
            if (lat != null && lon != null && lat != 0 && lon != 0) {
              return (lat, lon);
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  // ── Helpers ──

  void _searchCoords() {
    final lat = _lat;
    final lon = _lon;
    if (lat == null || lon == null) {
      setState(() => _error = 'Enter valid coordinates');
      return;
    }
    setState(() { _error = null; _marker = LatLng(lat, lon); });
    _moveToMarker(_coordZoom);
    _persist();
  }

  void _moveToMarker(double zoom) {
    if (_marker != null) _mapController.move(_marker!, zoom);
  }

  void _zoomIn() {
    final cam = _mapController.camera;
    _mapController.move(_marker ?? cam.center, (cam.zoom + 1).clamp(2.0, 18.0));
  }

  void _zoomOut() {
    final cam = _mapController.camera;
    _mapController.move(_marker ?? cam.center, (cam.zoom - 1).clamp(2.0, 18.0));
  }

  Future<void> _openOSM() async {
    final lat = _lat ?? _defaultLat;
    final lon = _lon ?? _defaultLon;
    final z = _marker != null ? _coordZoom.round() : _defaultZoom.round();
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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(mapStateProvider);
    final tileLayer = saved.tileLayer;

    final initialCenter = _marker
        ?? (saved.lat != null && saved.lon != null
            ? LatLng(saved.lat!, saved.lon!)
            : const LatLng(_defaultLat, _defaultLon));
    final initialZoom = _marker != null ? _coordZoom : saved.zoom;

    return Row(children: [
      // Resize handle (left edge)
      MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragUpdate: (d) {
            setState(() {
              _panelWidth = (_panelWidth - d.delta.dx).clamp(200.0, 500.0);
            });
          },
          child: Container(
            width: 5,
            color: _kBorder,
          ),
        ),
      ),
      // Main panel
      SizedBox(
        width: _panelWidth,
        child: Container(
          color: _kBg,
          child: Column(children: [
            // ── Header bar ──
            _buildHeader(tileLayer),
            // ── Map ──
            Expanded(child: _buildMap(initialCenter, initialZoom, tileLayer)),
            // ── Coord panel (toggleable) ──
            if (_showCoords) _buildCoordPanel(),
            // ── Info bar ──
            _buildInfoBar(),
          ]),
        ),
      ),
    ]);
  }

  // ── Header ──

  Widget _buildHeader(int tileLayer) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder, width: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.map_rounded, size: 12, color: _kCyan),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _gpsTrack != null
                ? '${_currentSpeed.round()} km/h  ·  $_currentTime'
                : _error ?? 'GPS Map',
            style: TextStyle(
              color: _error != null ? Colors.orange : _kText1,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Layer toggle
        _HeaderBtn(
          icon: Icons.layers_rounded,
          tooltip: _tileLayers[tileLayer].label,
          onTap: () {
            final next = (tileLayer + 1) % _tileLayers.length;
            ref.read(mapStateProvider.notifier).state =
                ref.read(mapStateProvider).copyWith(tileLayer: next);
          },
        ),
        // Coord toggle
        _HeaderBtn(
          icon: Icons.edit_location_alt_rounded,
          tooltip: 'Coordinates',
          active: _showCoords,
          onTap: () => setState(() => _showCoords = !_showCoords),
        ),
        // External links
        _HeaderBtn(
          icon: Icons.open_in_new_rounded,
          tooltip: 'Open in browser',
          onTap: _openOSM,
        ),
        // Close
        _HeaderBtn(
          icon: Icons.close_rounded,
          tooltip: 'Close map (M)',
          onTap: () {
            _persist();
            widget.onClose?.call();
          },
        ),
      ]),
    );
  }

  // ── Map ──

  Widget _buildMap(LatLng center, double zoom, int tileLayer) {
    return Stack(children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
          minZoom: 2,
          maxZoom: 18,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
          onPositionChanged: (_, hasGesture) {
            if (hasGesture) _autoFollow = false;
          },
        ),
        children: [
          TileLayer(
            urlTemplate: _tileLayers[tileLayer].url,
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.dashcam.player',
            maxZoom: 18,
          ),
          // GPS polyline trail
          if (_gpsTrack != null && _gpsTrack!.length > 1)
            PolylineLayer(polylines: [
              Polyline(
                points: _gpsTrack!.map((p) => LatLng(p.$2, p.$3)).toList(),
                color: _kCyan,
                strokeWidth: 3.0,
              ),
            ]),
          // Marker with speed
          if (_marker != null)
            MarkerLayer(markers: [
              Marker(
                point: _marker!,
                width: 80, height: 55,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_gpsTrack != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: _kCyan, width: 0.5),
                        ),
                        child: Text(
                          '${_currentSpeed.round()} km/h',
                          style: const TextStyle(
                              color: _kCyan,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    const Icon(Icons.navigation, color: Colors.red, size: 22),
                  ],
                ),
              ),
            ]),
        ],
      ),

      // Zoom + recenter buttons
      Positioned(
        right: 6,
        bottom: 6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapBtn(icon: Icons.add, onTap: _zoomIn),
            const SizedBox(height: 3),
            _MapBtn(icon: Icons.remove, onTap: _zoomOut),
            const SizedBox(height: 3),
            _MapBtn(
              icon: Icons.my_location_rounded,
              onTap: () {
                _autoFollow = true;
                if (_marker != null) _mapController.move(_marker!, _coordZoom);
              },
            ),
          ],
        ),
      ),

      // Attribution
      const Positioned(
        left: 4, bottom: 2,
        child: Text('\u00A9 OpenStreetMap',
            style: TextStyle(color: Colors.black45, fontSize: 7)),
      ),

      // Loading
      if (_loading)
        const Center(
          child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _kCyan)),
        ),
    ]);
  }

  // ── Coord panel ──

  Widget _buildCoordPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kBorder, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: _CoordField(
                label: 'Lat', controller: _latCtrl,
                onSubmitted: _searchCoords,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _CoordField(
                label: 'Lon', controller: _lonCtrl,
                onSubmitted: _searchCoords,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _searchCoords,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _kCyan, borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.search_rounded,
                    size: 12, color: Colors.black),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _ChipBtn(
              icon: Icons.my_location_rounded,
              label: 'My location',
              onTap: _loading ? null : _tryDeviceLocation,
            ),
            const SizedBox(width: 4),
            if (widget.videoPath != null)
              _ChipBtn(
                icon: Icons.refresh_rounded,
                label: 'Re-extract',
                onTap: _loading ? null : _tryExtractGPS,
              ),
            const SizedBox(width: 4),
            _ChipBtn(
              icon: Icons.map_outlined,
              label: 'Google Maps',
              onTap: _openGoogleMaps,
            ),
          ]),
        ],
      ),
    );
  }

  // ── Info bar ──

  Widget _buildInfoBar() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kBorder, width: 0.5)),
      ),
      child: Row(children: [
        if (_gpsTrack != null)
          Text('${_gpsTrack!.length} pts',
              style: const TextStyle(color: _kText3, fontSize: 9)),
        const Spacer(),
        if (_marker != null)
          Text(
            '${_marker!.latitude.toStringAsFixed(4)}, ${_marker!.longitude.toStringAsFixed(4)}',
            style: const TextStyle(
                color: _kText3, fontSize: 9, fontFamily: 'monospace'),
          ),
      ]),
    );
  }
}

// ─── Helper widgets ─────────────────────────────────────────────────────────

class _HeaderBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  const _HeaderBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 22, height: 22,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: widget.active
                  ? _kCyan.withValues(alpha: 0.15)
                  : _hovered
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon,
                size: 12,
                color: widget.active
                    ? _kCyan
                    : _hovered ? _kText1 : _kText3),
          ),
        ),
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 3,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Icon(icon, size: 14, color: Colors.black87),
      ),
    );
  }
}

class _CoordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  const _CoordField({
    required this.label,
    required this.controller,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-+]')),
      ],
      onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
      style: const TextStyle(color: _kText1, fontSize: 10),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kText3, fontSize: 9),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kCyan),
        ),
      ),
    );
  }
}

class _ChipBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ChipBtn({required this.icon, required this.label, this.onTap});

  @override
  State<_ChipBtn> createState() => _ChipBtnState();
}

class _ChipBtnState extends State<_ChipBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: _hovered
                ? _kCyan.withValues(alpha: 0.15)
                : _kCyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
                color: _kCyan.withValues(alpha: _hovered ? 0.4 : 0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 10, color: _kCyan),
            const SizedBox(width: 3),
            Text(widget.label,
                style: const TextStyle(
                    color: _kCyan,
                    fontSize: 8,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
