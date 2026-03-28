// lib/models/gps_point.dart

class GpsPoint {
  final Duration timestamp;
  final double lat;
  final double lon;
  final double? speed; // km/h

  const GpsPoint({
    required this.timestamp,
    required this.lat,
    required this.lon,
    this.speed,
  });

  @override
  String toString() =>
      'GpsPoint(${timestamp.inSeconds}s, $lat, $lon${speed != null ? ', ${speed}km/h' : ''})';
}
