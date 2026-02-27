import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import '../local_database.dart';
import '../data_model.dart';
import 'path_analysis_service.dart';
import '../utils/privacy_utils.dart';
import 'dart:math' as math;

/// سرویس Export داده‌ها برای پژوهشگر
class DataExportService {
  final LocalDatabase _database;
  final PathAnalysisService _pathAnalysis;

  DataExportService(this._database) : _pathAnalysis = PathAnalysisService(_database);

  /// Export تمام داده‌ها به CSV با اطلاعات کامل برای تحلیل مسیر
  Future<String> exportAllDataToCsv() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'wifi_knn_data_$timestamp.csv';

    // دریافت تمام داده‌ها
    final fingerprints = await _database.getAllFingerprints();
    final wifiScans = await _database.getAllWifiScans();
    final locationHistory = await _database.getAllLocationHistory();

    // دریافت Device ID فعلی
    final currentDeviceId = await PrivacyUtils.getDeviceId();

    // محاسبه اطلاعات مسیر برای هر کاربر
    final allDeviceIds = <String>{};
    for (final loc in locationHistory) {
      allDeviceIds.add(loc.deviceId);
    }
    for (final scan in wifiScans) {
      allDeviceIds.add(scan.deviceId);
    }
    for (final fp in fingerprints) {
      if (fp.deviceId != null) {
        allDeviceIds.add(fp.deviceId!);
      }
    }

    // ساخت CSV با Header بهبود یافته
    final csvData = <List<dynamic>>[];

    // Header بهبود یافته برای تحلیل مسیر
    csvData.add([
      'Type',
      'ID',
      'Device ID',
      'Session ID',
      'Context',
      'Timestamp',
      'Date',
      'Time',
      'Latitude',
      'Longitude',
      'Zone Label',
      'Confidence',
      'BSSID',
      'RSSI',
      'Frequency',
      'SSID',
      'Distance From Previous (m)',
      'Time Since Previous (s)',
      'Speed (m/s)',
      'Path Segment Index',
      'Total Path Length (m)',
      'Zone Presence Time (s)',
    ]);

    // محاسبه اطلاعات مسیر برای هر کاربر
    final pathStatisticsByDevice = <String, Map<String, dynamic>>{};
    final zonePresenceTimeByDevice = <String, Map<String, int>>{};
    
    for (final deviceId in allDeviceIds) {
      try {
        pathStatisticsByDevice[deviceId] = await _pathAnalysis.getPathStatistics(deviceId);
        zonePresenceTimeByDevice[deviceId] = await _pathAnalysis.calculateZonePresenceTime(deviceId);
      } catch (e) {
        debugPrint('Error calculating path statistics for device $deviceId: $e');
      }
    }

    // دسته‌بندی Location History بر اساس Device ID و مرتب‌سازی بر اساس زمان
    final locationHistoryByDevice = <String, List<LocationHistoryEntry>>{};
    for (final loc in locationHistory) {
      locationHistoryByDevice.putIfAbsent(loc.deviceId, () => []).add(loc);
    }
    
    for (final deviceId in locationHistoryByDevice.keys) {
      locationHistoryByDevice[deviceId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    // Fingerprints
    for (final fp in fingerprints) {
      final deviceId = fp.deviceId ?? '';
      final totalPathLength = pathStatisticsByDevice[deviceId]?['total_distance_meters'] ?? 0.0;
      final zonePresenceTime = zonePresenceTimeByDevice[deviceId]?[fp.zoneLabel ?? ''] ?? 0;
      
      for (final ap in fp.accessPoints) {
        final timestamp = fp.createdAt;
        csvData.add([
          'Fingerprint',
          fp.fingerprintId,
          deviceId,
          fp.sessionId ?? '',
          fp.contextId ?? '',
          timestamp.toIso8601String(),
          '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}',
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}',
          fp.latitude,
          fp.longitude,
          fp.zoneLabel ?? '',
          '',
          ap.bssid,
          ap.rssi,
          ap.frequency ?? '',
          ap.ssid ?? '',
          '', // Distance From Previous
          '', // Time Since Previous
          '', // Speed
          '', // Path Segment Index
          totalPathLength,
          zonePresenceTime,
        ]);
      }
    }

    // WiFi Scans
    for (final scan in wifiScans) {
      final deviceId = scan.deviceId;
      final timestamp = scan.timestamp;
      
      final readings = await _database.getWifiScanReadings(scan.id!);
      for (final reading in readings) {
        csvData.add([
          'WiFi Scan',
          scan.id.toString(),
          deviceId,
          '', // Session
          '', // Context
          timestamp.toIso8601String(),
          '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}',
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}',
          '',
          '',
          '',
          '',
          reading.bssid,
          reading.rssi,
          reading.frequency ?? '',
          reading.ssid ?? '',
          '', // Distance From Previous
          '', // Time Since Previous
          '', // Speed
          '', // Path Segment Index
          '', // Total Path Length
          '', // Zone Presence Time
        ]);
      }
    }

    // Location History با محاسبه فاصله و زمان از نقطه قبلی
    for (final deviceId in locationHistoryByDevice.keys) {
      final path = locationHistoryByDevice[deviceId]!;
      final totalPathLength = pathStatisticsByDevice[deviceId]?['total_distance_meters'] ?? 0.0;
      final zonePresenceTimes = zonePresenceTimeByDevice[deviceId] ?? {};
      
      for (int i = 0; i < path.length; i++) {
        final loc = path[i];
        final timestamp = loc.timestamp;
        
        double distanceFromPrevious = 0.0;
        int timeSincePrevious = 0;
        double speed = 0.0;
        
        if (i > 0) {
          final previous = path[i - 1];
          
          // محاسبه فاصله با استفاده از فرمول Haversine
          distanceFromPrevious = _calculateHaversineDistance(
            previous.latitude,
            previous.longitude,
            loc.latitude,
            loc.longitude,
          );
          
          timeSincePrevious = timestamp.difference(previous.timestamp).inSeconds;
          speed = timeSincePrevious > 0 ? distanceFromPrevious / timeSincePrevious : 0.0;
        }
        
        final zonePresenceTime = zonePresenceTimes[loc.zoneLabel ?? ''] ?? 0;
        
        csvData.add([
          'Location History',
          loc.id.toString(),
          deviceId,
          '', // Session
          '', // Context
          timestamp.toIso8601String(),
          '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}',
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}',
          loc.latitude,
          loc.longitude,
          loc.zoneLabel ?? '',
          loc.confidence,
          '', // BSSID
          '', // RSSI
          '', // Frequency
          '', // SSID
          distanceFromPrevious.toStringAsFixed(2),
          timeSincePrevious,
          speed.toStringAsFixed(2),
          i,
          totalPathLength,
          zonePresenceTime,
        ]);
      }
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

  /// دانلود مستقیم فایل CSV به پوشه Download
  Future<String?> downloadCsvToDownloads() async {
    try {
      // تولید فایل CSV
      final filePath = await exportAllDataToCsv();
      final file = File(filePath);
      
      if (!await file.exists()) {
        debugPrint('CSV file does not exist: $filePath');
        return null;
      }

      // خواندن محتوای فایل
      final csvContent = await file.readAsString();

      // درخواست دسترسی
      if (!await Permission.storage.request().isGranted) {
        debugPrint('Storage permission not granted');
        return null;
      }

      try {
        // مسیر پوشه دانلود اندروید
        final Directory downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          debugPrint('Downloads directory does not exist');
          return null;
        }

        // نام فایل با timestamp
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final fileName = 'wifi_knn_data_$timestamp.csv';
        final outFile = File('${downloadsDir.path}/$fileName');
        
        // ذخیره فایل
        await outFile.writeAsString(csvContent, flush: true);
        
        debugPrint('CSV file saved to Downloads: ${outFile.path}');
        return outFile.path;
      } catch (e) {
        debugPrint('Error saving CSV to Downloads: $e');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading CSV file: $e');
      rethrow;
    }
  }

  /// دانلود و اشتراک‌گذاری فایل CSV (برای سازگاری با کد قدیمی)
  Future<void> downloadAndShareCsv() async {
    try {
      final downloadedPath = await downloadCsvToDownloads();
      if (downloadedPath != null) {
        // باز کردن فایل بعد از دانلود
        await OpenFile.open(downloadedPath);
      } else {
        throw 'خطا در دانلود فایل CSV';
      }
    } catch (e) {
      debugPrint('Error downloading CSV file: $e');
      rethrow;
    }
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

  /// محاسبه فاصله بین دو نقطه با استفاده از فرمول Haversine (به متر)
  double _calculateHaversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // متر

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}

