import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import '../local_database.dart';
import '../data_model.dart';

/// سرویس Export داده‌ها برای پژوهشگر
class DataExportService {
  final LocalDatabase _database;

  DataExportService(this._database);

  /// Export تمام داده‌ها به CSV
  Future<String> exportAllDataToCsv() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'wifi_knn_data_$timestamp.csv';

    // دریافت تمام داده‌ها
    final fingerprints = await _database.getAllFingerprints();
    final wifiScans = await _database.getAllWifiScans();
    final locationHistory = await _database.getAllLocationHistory();

    // ساخت CSV
    final csvData = <List<dynamic>>[];

    // Header
    csvData.add([
      'Type',
      'ID',
      'Timestamp',
      'Latitude',
      'Longitude',
      'Zone Label',
      'BSSID',
      'RSSI',
      'Frequency',
      'SSID',
      'Confidence',
      'Device ID',
    ]);

    // Fingerprints
    for (final fp in fingerprints) {
      for (final ap in fp.accessPoints) {
        csvData.add([
          'Fingerprint',
          fp.fingerprintId,
          fp.createdAt.toIso8601String(),
          fp.latitude,
          fp.longitude,
          fp.zoneLabel ?? '',
          ap.bssid,
          ap.rssi,
          ap.frequency ?? '',
          ap.ssid ?? '',
          '',
          fp.deviceId ?? '',
        ]);
      }
    }

    // WiFi Scans
    for (final scan in wifiScans) {
      final readings = await _database.getWifiScanReadings(scan.id!);
      for (final reading in readings) {
        csvData.add([
          'WiFi Scan',
          scan.id.toString(),
          scan.timestamp.toIso8601String(),
          '',
          '',
          '',
          reading.bssid,
          reading.rssi,
          reading.frequency ?? '',
          reading.ssid ?? '',
          '',
          scan.deviceId,
        ]);
      }
    }

    // Location History
    for (final loc in locationHistory) {
      csvData.add([
        'Location History',
        loc.id.toString(),
        loc.timestamp.toIso8601String(),
        loc.latitude,
        loc.longitude,
        loc.zoneLabel ?? '',
        '',
        '',
        '',
        '',
        loc.confidence,
        loc.deviceId,
      ]);
    }

    // تبدیل به CSV string
    final csvString = const ListToCsvConverter().convert(csvData);

    // ذخیره فایل
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvString);

    debugPrint('Data exported to: ${file.path}');
    return file.path;
  }

  /// Export به JSON
  Future<String> exportAllDataToJson() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'wifi_knn_data_$timestamp.json';

    final data = <String, dynamic>{
      'export_timestamp': DateTime.now().toIso8601String(),
      'fingerprints': [],
      'wifi_scans': [],
      'location_history': [],
    };

    // Fingerprints
    final fingerprints = await _database.getAllFingerprints();
    for (final fp in fingerprints) {
      data['fingerprints']!.add(fp.toMap());
    }

    // WiFi Scans
    final wifiScans = await _database.getAllWifiScans();
    for (final scan in wifiScans) {
      final readings = await _database.getWifiScanReadings(scan.id!);
      data['wifi_scans']!.add({
        ...scan.toMap(),
        'readings': readings.map((r) => r.toMap()).toList(),
      });
    }

    // Location History
    final locationHistory = await _database.getAllLocationHistory();
    for (final loc in locationHistory) {
      data['location_history']!.add(loc.toMap());
    }

    // تبدیل به JSON
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    // ذخیره فایل
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonString);

    debugPrint('Data exported to: ${file.path}');
    return file.path;
  }

  /// Export آمار و خلاصه
  Future<Map<String, dynamic>> getStatistics() async {
    final fingerprints = await _database.getAllFingerprints();
    final wifiScans = await _database.getAllWifiScans();
    final locationHistory = await _database.getAllLocationHistory();

    // محاسبه آمار
    final uniqueBssids = <String>{};
    final bssidCounts = <String, int>{};
    double totalConfidence = 0.0;
    int confidenceCount = 0;

    for (final fp in fingerprints) {
      for (final ap in fp.accessPoints) {
        uniqueBssids.add(ap.bssid);
        bssidCounts[ap.bssid] = (bssidCounts[ap.bssid] ?? 0) + 1;
      }
    }

    for (final loc in locationHistory) {
      if (loc.confidence > 0) {
        totalConfidence += loc.confidence;
        confidenceCount++;
      }
    }

    return {
      'total_fingerprints': fingerprints.length,
      'total_wifi_scans': wifiScans.length,
      'total_location_estimates': locationHistory.length,
      'unique_bssids': uniqueBssids.length,
      'average_confidence': confidenceCount > 0 ? totalConfidence / confidenceCount : 0.0,
      'most_common_bssids': bssidCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..take(10)
        ..map((e) => {'bssid': e.key, 'count': e.value})
        ..toList(),
    };
  }
}

