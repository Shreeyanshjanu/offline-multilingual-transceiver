class GpsLocation {
  const GpsLocation({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.timestamp,
    this.provider,
  });

  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final DateTime? timestamp;
  final String? provider;

  /// Returns coordinates formatted as "28.6139° N, 77.2090° E".
  String get formattedCoordinates {
    final String latDir = latitude >= 0 ? 'N' : 'S';
    final String lngDir = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(4)}° $latDir, ${longitude.abs().toStringAsFixed(4)}° $lngDir';
  }

  /// Returns compact coordinates e.g. "28.6139, 77.2090".
  String get compactCoordinates =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  /// Returns accuracy label e.g. "±4m".
  String get accuracyLabel =>
      accuracy == null ? '' : '±${accuracy!.toStringAsFixed(0)}m';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lat': latitude,
      'lng': longitude,
      if (altitude != null) 'alt': altitude,
      if (accuracy != null) 'acc': accuracy,
      if (timestamp != null) 'timestamp': timestamp!.millisecondsSinceEpoch,
      if (provider != null) 'provider': provider,
    };
  }

  factory GpsLocation.fromJson(Map<String, dynamic> json) {
    final Object? latRaw = json['lat'] ?? json['latitude'];
    final Object? lngRaw = json['lng'] ?? json['lon'] ?? json['longitude'];
    final Object? altRaw = json['alt'] ?? json['altitude'];
    final Object? accRaw = json['acc'] ?? json['accuracy'];
    final Object? tsRaw = json['timestamp'];

    final double lat = switch (latRaw) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0.0,
      _ => 0.0,
    };

    final double lng = switch (lngRaw) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0.0,
      _ => 0.0,
    };

    final double? alt = switch (altRaw) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

    final double? acc = switch (accRaw) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

    final DateTime? ts = switch (tsRaw) {
      int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      num n => DateTime.fromMillisecondsSinceEpoch(n.toInt()),
      String s => int.tryParse(s) != null
          ? DateTime.fromMillisecondsSinceEpoch(int.parse(s))
          : DateTime.tryParse(s),
      _ => null,
    };

    return GpsLocation(
      latitude: lat,
      longitude: lng,
      altitude: alt,
      accuracy: acc,
      timestamp: ts,
      provider: json['provider']?.toString(),
    );
  }

  GpsLocation copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? accuracy,
    DateTime? timestamp,
    String? provider,
  }) {
    return GpsLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      provider: provider ?? this.provider,
    );
  }

  @override
  String toString() =>
      'GpsLocation($compactCoordinates, acc: $accuracyLabel, provider: $provider)';
}
