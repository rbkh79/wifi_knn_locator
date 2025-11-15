/// مدل‌های داده برای اپلیکیشن

import 'config.dart';

/// خواندن Wi-Fi (نقطه دسترسی مشاهده شده)
class WifiReading {
  final String bssid; // MAC address (BSSID)
  final int rssi; // قدرت سیگنال
  final int? frequency; // فرکانس (MHz) - اختیاری
  final String? ssid; // نام شبکه - اختیاری

  WifiReading({
    required this.bssid,
    required this.rssi,
    this.frequency,
    this.ssid,
  });

  Map<String, dynamic> toMap() {
    return {
      'bssid': bssid,
      'rssi': rssi,
      'frequency': frequency,
      'ssid': ssid,
    };
  }

  factory WifiReading.fromMap(Map<String, dynamic> map) {
    return WifiReading(
      bssid: map['bssid'] as String,
      rssi: map['rssi'] as int,
      frequency: map['frequency'] as int?,
      ssid: map['ssid'] as String?,
    );
  }

  @override
  String toString() => 'WifiReading(bssid: $bssid, rssi: $rssi, freq: $frequency)';
}

/// اسکن کامل Wi-Fi (شامل چندین WifiReading)
class WifiScanResult {
  final String deviceId; // شناسه هش‌شده دستگاه
  final DateTime timestamp;
  final List<WifiReading> accessPoints;

  WifiScanResult({
    required this.deviceId,
    required this.timestamp,
    required this.accessPoints,
  });

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'access_points': accessPoints.map((ap) => ap.toMap()).toList(),
    };
  }

  factory WifiScanResult.fromMap(Map<String, dynamic> map) {
    return WifiScanResult(
      deviceId: map['device_id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      accessPoints: (map['access_points'] as List)
          .map((ap) => WifiReading.fromMap(ap as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// ورودی اثرانگشت (Fingerprint Entry) در پایگاه داده
class FingerprintEntry {
  final int? id; // شناسه در پایگاه داده (null برای ورودی جدید)
  final String fingerprintId; // شناسه یکتا اثرانگشت
  final double latitude;
  final double longitude;
  final String? zoneLabel; // لیبل ناحیه (اختیاری)
  final List<WifiReading> accessPoints;
  final DateTime createdAt;
  final String? deviceId; // شناسه دستگاه که این اثرانگشت را ثبت کرده

  FingerprintEntry({
    this.id,
    required this.fingerprintId,
    required this.latitude,
    required this.longitude,
    this.zoneLabel,
    required this.accessPoints,
    required this.createdAt,
    this.deviceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fingerprint_id': fingerprintId,
      'latitude': latitude,
      'longitude': longitude,
      'zone_label': zoneLabel,
      'access_points': accessPoints.map((ap) => ap.toMap()).toList(),
      'created_at': createdAt.toIso8601String(),
      'device_id': deviceId,
    };
  }

  factory FingerprintEntry.fromMap(Map<String, dynamic> map) {
    return FingerprintEntry(
      id: map['id'] as int?,
      fingerprintId: map['fingerprint_id'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      zoneLabel: map['zone_label'] as String?,
      accessPoints: (map['access_points'] as List)
          .map((ap) => WifiReading.fromMap(ap as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
      deviceId: map['device_id'] as String?,
    );
  }

  /// تبدیل به فرمت قدیمی برای سازگاری با CSV
  Map<String, dynamic> toLegacyMap() {
    final map = <String, dynamic>{
      'lat': latitude,
      'lon': longitude,
    };
    for (final ap in accessPoints) {
      map[ap.bssid] = ap.rssi;
    }
    return map;
  }
}

/// تخمین موقعیت (Location Estimate)
class LocationEstimate {
  final double latitude;
  final double longitude;
  final double confidence; // ضریب اطمینان (0.0 تا 1.0)
  final String? zoneLabel; // لیبل ناحیه تخمینی
  final List<FingerprintEntry> nearestNeighbors; // k همسایه نزدیک
  final double averageDistance; // میانگین فاصله تا همسایه‌ها

  LocationEstimate({
    required this.latitude,
    required this.longitude,
    required this.confidence,
    this.zoneLabel,
    required this.nearestNeighbors,
    required this.averageDistance,
  });

  bool get isReliable => confidence >= AppConfig.confidenceThreshold;

  @override
  String toString() =>
      'LocationEstimate(lat: $latitude, lon: $longitude, confidence: ${confidence.toStringAsFixed(2)})';
}

/// رکورد فاصله برای KNN
class DistanceRecord {
  final double distance;
  final FingerprintEntry fingerprint;
  final int index;

  DistanceRecord({
    required this.distance,
    required this.fingerprint,
    required this.index,
  });
}

