// lib/widgets/map_dialog.dart
//
// Interactive OpenStreetMap sidebar with coordinate input, search, zoom/pan,
// multiple tile layers, and browser-open buttons.  State (coordinates, zoom,
// tile layer) is persisted via Riverpod so it survives open/close cycles.
// Shows device location by default on first open.

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

// Default: centre of India
const double _defaultLat  = 20.5937;
const double _defaultLon  = 78.9629;
const double _defaultZoom = 5;
const double _coordZoom   = 15;
const double _minWidth    = 280;
const double _maxWidth    = 600;

class MapSidebar extends ConsumerStatefulWidget {
  final String? videoPath;
  final VoidCallback? onClose;
  const MapSidebar({super.key, this.videoPath, this.onClose});

  @override
  ConsumerState<MapSidebar> createState() => _MapSidebarState();
}

class _MapSidebarState extends ConsumerState<MapSidebar> {
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _mapController = MapController();

  bool    _loading = false;
  String? _error;
  double  _width   = 340;

  // Marker position (null = no marker)
  LatLng? _marker;

  // GPS track for synced map (from .ts files)
  List<(double, double, double)>? _gpsTrack; // (seconds, lat, lon)
  bool _trackSyncing = false;
  StreamSubscription? _trackSub;

  static const _tileLayers = [
    (label: 'Standard', url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    (label: 'Topo',     url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'),
    (label: 'HOT',      url: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png'),
  ];

  @override
  void initState() {
    super.initState();
    // Always try extracting GPS from current video first
    if (widget.videoPath != null) {
      _tryExtractGPS();
    } else {
      // Restore persisted state or get device location
      final saved = ref.read(mapStateProvider);
      if (saved.lat != null && saved.lon != null) {
        _latCtrl.text = saved.lat!.toStringAsFixed(6);
        _lonCtrl.text = saved.lon!.toStringAsFixed(6);
        _marker = LatLng(saved.lat!, saved.lon!);
      } else {
        _tryDeviceLocation();
      }
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
    _trackSub?.cancel();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Save current state to provider so it survives sidebar close/reopen.
  void _persist() {
    if (!mounted) return;
    try {
      final cam = _mapController.camera;
      ref.read(mapStateProvider.notifier).state = MapState(
        lat:       _lat,
        lon:       _lon,
        zoom:      cam.zoom,
        tileLayer: ref.read(mapStateProvider).tileLayer,
      );
    } catch (_) {
      try {
        ref.read(mapStateProvider.notifier).state = MapState(
          lat: _lat,
          lon: _lon,
        );
      } catch (_) {}
    }
  }

  double? get _lat => double.tryParse(_latCtrl.text.trim());
  double? get _lon => double.tryParse(_lonCtrl.text.trim());

  /// Try to get device location using platform-specific commands.
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
        appLog('Map', 'Device location: ${coords.$1}, ${coords.$2}');
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Get device GPS location via Windows.Devices.Geolocation (UWP API).
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

  Future<void> _tryExtractGPS() async {
    setState(() { _loading = true; _error = null; _gpsTrack = null; _trackSyncing = false; });

    // Try extracting GPS track (per-second points for synced map)
    final track = await ExportService.extractGPSTrack(widget.videoPath!);
    if (!mounted) return;
    if (track != null && track.isNotEmpty) {
      _gpsTrack = track;
      _trackSyncing = true;
      // Set initial marker to first point
      final (_, lat, lon) = track.first;
      _latCtrl.text = lat.toStringAsFixed(6);
      _lonCtrl.text = lon.toStringAsFixed(6);
      _marker = LatLng(lat, lon);
      _moveToMarker(_coordZoom);
      _persist();
      appLog('Map', 'GPS track loaded: ${track.length} points');
      if (mounted) setState(() => _loading = false);
      _startTrackSync();
      return;
    }

    // Fall back to single GPS extraction
    final coords = await ExportService.extractGPS(widget.videoPath!);
    if (!mounted) return;
    if (coords != null) {
      _latCtrl.text = coords.$1.toStringAsFixed(6);
      _lonCtrl.text = coords.$2.toStringAsFixed(6);
      _marker = LatLng(coords.$1, coords.$2);
      _moveToMarker(_coordZoom);
      appLog('Map', 'GPS extracted: ${coords.$1}, ${coords.$2}');
    } else {
      // No GPS in video metadata — try device location as fallback
      if (_marker == null) {
        await _tryDeviceLocation();
        if (_marker == null) {
          _error = 'No GPS data found. Enter coordinates manually.';
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Sync map marker with video playback position using GPS track.
  void _startTrackSync() {
    _trackSub?.cancel();
    if (_gpsTrack == null || !_trackSyncing) return;

    // Use whichever player is active (front preferred)
    final notifier = ref.read(playbackProvider.notifier);
    final playback = ref.read(playbackProvider);
    final player = playback.hasFront ? notifier.frontPlayer : notifier.backPlayer;

    _trackSub = player.stream.position.listen((pos) {
      if (!mounted || !_trackSyncing || _gpsTrack == null) return;
      final secs = pos.inMilliseconds / 1000.0;

      // Binary-search style: find closest GPS point to current playback position
      (double, double, double)? closest;
      double minDiff = double.infinity;
      for (final point in _gpsTrack!) {
        final diff = (point.$1 - secs).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = point;
        }
        // Points are sorted by time; if diff starts increasing, stop early
        if (diff > minDiff) break;
      }

      if (closest != null && minDiff < 2.0) {
        final (_, lat, lon) = closest;
        if (_marker == null || _marker!.latitude != lat || _marker!.longitude != lon) {
          final newMarker = LatLng(lat, lon);
          setState(() {
            _marker = newMarker;
            _latCtrl.text = lat.toStringAsFixed(6);
            _lonCtrl.text = lon.toStringAsFixed(6);
          });
          try {
            _mapController.move(newMarker, _mapController.camera.zoom);
          } catch (_) {}
        }
      }
    });
  }

  void _searchCoords() {
    final lat = _lat;
    final lon = _lon;
    if (lat == null || lon == null) {
      setState(() => _error = 'Enter valid coordinates.');
      return;
    }
    setState(() {
      _error = null;
      _marker = LatLng(lat, lon);
    });
    _moveToMarker(_coordZoom);
    _persist();
    appLog('Map', 'Search: $lat, $lon');
  }

  void _moveToMarker(double zoom) {
    if (_marker != null) {
      _mapController.move(_marker!, zoom);
    }
  }

  void _zoomIn() {
    final cam = _mapController.camera;
    final newZoom = (cam.zoom + 1).clamp(2.0, 18.0);
    final target = _marker ?? cam.center;
    _mapController.move(target, newZoom);
  }

  void _zoomOut() {
    final cam = _mapController.camera;
    final newZoom = (cam.zoom - 1).clamp(2.0, 18.0);
    final target = _marker ?? cam.center;
    _mapController.move(target, newZoom);
  }

  Future<void> _openOSM() async {
    final lat = _lat ?? _defaultLat;
    final lon = _lon ?? _defaultLon;
    final z   = _marker != null ? _coordZoom.round() : _defaultZoom.round();
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
    final saved     = ref.watch(mapStateProvider);
    final tileLayer = saved.tileLayer;

    final initialCenter = _marker
        ?? (saved.lat != null && saved.lon != null
            ? LatLng(saved.lat!, saved.lon!)
            : const LatLng(_defaultLat, _defaultLon));
    final initialZoom = _marker != null ? _coordZoom : saved.zoom;

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      width: _width,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                    // ─── Header ───────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
                      color: const Color(0xFF1A1A1A),
                      child: Row(children: [
                        const Icon(Icons.map_rounded,
                            color: Color(0xFF4FC3F7), size: 18),
                        const SizedBox(width: 6),
                        const Text('GPS / Map',
                          style: TextStyle(color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w600)),
                        if (_trackSyncing && _gpsTrack != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.sync_rounded,
                                  size: 10, color: Color(0xFF4FC3F7)),
                              const SizedBox(width: 3),
                              Text('${_gpsTrack!.length}pts',
                                style: const TextStyle(color: Color(0xFF4FC3F7),
                                    fontSize: 9, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ],
                        const Spacer(),
                        _IconBtn(
                          icon: Icons.my_location_rounded,
                          tooltip: 'My location',
                          onTap: _loading ? null : _tryDeviceLocation,
                        ),
                        if (widget.videoPath != null)
                          _IconBtn(
                            icon: Icons.refresh_rounded,
                            tooltip: 'Re-extract GPS from video',
                            onTap: _loading ? null : _tryExtractGPS,
                          ),
                        _IconBtn(
                          icon: Icons.close_rounded,
                          tooltip: 'Close (M)',
                          onTap: () {
                            _persist();
                            Navigator.of(context).pop();
                            widget.onClose?.call();
                          },
                        ),
                      ]),
                    ),

                    // ─── Coordinate inputs + actions ─────
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      color: const Color(0xFF1A1A1A),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Lat / Lon row
                          Row(children: [
                            Expanded(
                              child: _CoordInput(
                                label: 'Lat', hint: '20.5937',
                                controller: _latCtrl,
                                onSubmitted: _searchCoords,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _CoordInput(
                                label: 'Lon', hint: '78.9629',
                                controller: _lonCtrl,
                                onSubmitted: _searchCoords,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Search
                            _ActionIcon(
                              icon: Icons.search_rounded,
                              tooltip: 'Search coordinates',
                              onTap: _searchCoords,
                            ),
                          ]),

                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Center(child: SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF4FC3F7)))),
                            )
                          else ...[
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 10)),
                              ),
                            const SizedBox(height: 6),
                            // Action row: OSM, GMaps, tile layer
                            Row(children: [
                              _ActionChip(
                                icon: Icons.public_rounded,
                                label: 'OpenStreetMap',
                                onTap: _openOSM,
                              ),
                              const SizedBox(width: 6),
                              _ActionChip(
                                icon: Icons.map_outlined,
                                label: 'Google Maps',
                                onTap: _openGoogleMaps,
                              ),
                              const Spacer(),
                              _TileLayerBtn(
                                currentLayer: tileLayer,
                                onChanged: (i) {
                                  ref.read(mapStateProvider.notifier).state =
                                      saved.copyWith(tileLayer: i);
                                },
                              ),
                            ]),
                          ],
                        ],
                      ),
                    ),

                    // ─── Interactive map ─────────────────
                    Expanded(
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: initialZoom,
                          minZoom: 2,
                          maxZoom: 18,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: _tileLayers[tileLayer].url,
                            subdomains: const ['a', 'b', 'c'],
                            userAgentPackageName: 'com.dashcam.player',
                            maxZoom: 18,
                          ),
                          // GPS track polyline
                          if (_gpsTrack != null && _gpsTrack!.length > 1)
                            PolylineLayer(polylines: [
                              Polyline(
                                points: _gpsTrack!
                                    .map((p) => LatLng(p.$2, p.$3))
                                    .toList(),
                                color: const Color(0xFF4FC3F7),
                                strokeWidth: 3.0,
                              ),
                            ]),
                          // Marker
                          if (_marker != null)
                            MarkerLayer(markers: [
                              Marker(
                                point: _marker!,
                                width: 40, height: 40,
                                alignment: Alignment.topCenter,
                                child: const Icon(Icons.location_on,
                                    color: Colors.red, size: 40),
                              ),
                            ]),
                          // Zoom + re-center buttons
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ZoomBtn(icon: Icons.add, onTap: _zoomIn),
                                  const SizedBox(height: 4),
                                  _ZoomBtn(icon: Icons.remove, onTap: _zoomOut),
                                  const SizedBox(height: 4),
                                  _ZoomBtn(
                                    icon: Icons.my_location_rounded,
                                    onTap: () {
                                      if (_marker != null) {
                                        _mapController.move(
                                            _marker!, _coordZoom);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Attribution
                          const Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 2),
                              child: Text('\u00A9 OpenStreetMap contributors',
                                style: TextStyle(
                                    color: Colors.black54, fontSize: 8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ─── Resize handle (left edge) ──────────
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          _width = (_width - d.delta.dx).clamp(_minWidth, _maxWidth);
                        });
                      },
                      child: Container(width: 6, color: Colors.transparent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  }
}

// ─── Compact coordinate input ────────────────────────────────────────────────

class _CoordInput extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  const _CoordInput({
    required this.label, required this.hint, required this.controller,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-+]')),
      ],
      onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
      style: const TextStyle(color: Colors.white70, fontSize: 12),
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
        hintStyle:  const TextStyle(color: Colors.white24, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7))),
      ),
    );
  }
}

// ─── Action icon button (search) ─────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF4FC3F7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: Colors.black),
        ),
      ),
    );
  }
}

// ─── Action chip button ──────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: const Color(0xFF4FC3F7)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(
                color: Color(0xFF4FC3F7), fontSize: 10,
                fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ─── Tile layer switcher ─────────────────────────────────────────────────────

class _TileLayerBtn extends StatelessWidget {
  final int currentLayer;
  final ValueChanged<int> onChanged;
  const _TileLayerBtn({required this.currentLayer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      onSelected: onChanged,
      tooltip: 'Map style',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => [
        for (var i = 0; i < _MapSidebarState._tileLayers.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(children: [
              Icon(
                i == currentLayer ? Icons.check_rounded : Icons.layers_rounded,
                size: 14,
                color: i == currentLayer
                    ? const Color(0xFF4FC3F7) : Colors.white38,
              ),
              const SizedBox(width: 8),
              Text(_MapSidebarState._tileLayers[i].label,
                style: TextStyle(fontSize: 12,
                  color: i == currentLayer
                      ? const Color(0xFF4FC3F7) : Colors.white60)),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.layers_rounded, size: 14, color: Colors.white54),
          SizedBox(width: 3),
          Icon(Icons.arrow_drop_down_rounded, size: 14, color: Colors.white38),
        ]),
      ),
    );
  }
}

// ─── Small icon button ───────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white38, size: 18),
      onPressed: onTap,
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      splashRadius: 16,
    );
  }
}

// ─── Zoom button ─────────────────────────────────────────────────────────────

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Icon(icon, size: 18, color: Colors.black87),
      ),
    );
  }
}
