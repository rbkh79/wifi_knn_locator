import 'dart:convert';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'database_helper.dart';
import 'wifi_scanner.dart';
import 'data_model.dart';

/// لایه ساده‌تر روی WifiScanner با امکان حالت آموزش
class WifiService {
  /// اسکن زنده و برگشت نتیجه مرتب‌شده
  static Future<WifiScanResult> liveScan() async {
    return WifiScanner.performScan();
  }

  /// آموزش اثرانگشت: یک نقطه و لیست RSSI ذخیره می‌شود
  static Future<void> trainFingerprint({
    required LatLng location,
    required List<WifiReading> readings,
    String? zoneLabel,
  }) async {
    final vector = readings.map((r) => r.rssi).toList();
    await DatabaseHelper.insert('wifi_fingerprint_table', {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'rssi_vector': jsonEncode(vector),
      'zone_label': zoneLabel,
    });
  }

  /// نمونه‌گیری ترکیب RSSI برای تخمین ها از روی جدول
  static Future<LatLng?> estimatePosition(List<int> current) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('wifi_fingerprint_table');
    if (rows.isEmpty) return null;

    double bestWeight = 0;
    double sumLat = 0, sumLon = 0;
    const eps = 1e-3;

    for (final row in rows) {
      final saved = jsonDecode(row['rssi_vector'] as String) as List<dynamic>;
      final List<int> savedVec = saved.cast<int>();
      final dist = _euclidean(current, savedVec);
      final weight = 1 / (dist + eps);
      if (weight > bestWeight) bestWeight = weight;
      sumLat += (row['latitude'] as double) * weight;
      sumLon += (row['longitude'] as double) * weight;
    }
    if (bestWeight == 0) return null;
    return LatLng(sumLat / bestWeight, sumLon / bestWeight);
  }

  static double _euclidean(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    double sum = 0;
    for (var i = 0; i < n; i++) {
      final d = (a[i] - b[i]).toDouble();
      sum += d * d;
    }
    return sqrt(sum);
  }
}
