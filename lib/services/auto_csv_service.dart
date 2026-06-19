import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import '../data_model.dart';
import 'package:open_file/open_file.dart';

/// سرویس ذخیره خودکار CSV در هر اسکن Wi-Fi و BTS و GPS
///
/// داده‌ها در سه فایل جداگانه ذخیره می‌شوند:
/// 1. wifi_scans_auto.csv - فقط داده‌های WiFi
/// 2. gps_scans_auto.csv - فقط داده‌های GPS
/// 3. bts_scans_auto.csv - فقط داده‌های BTS
class AutoCsvService {
  static const String _wifiCsvFileName = 'wifi_scans_auto.csv';
  static const String _gpsCsvFileName = 'gps_scans_auto.csv';
  static const String _btsCsvFileName = 'bts_scans_auto.csv';
  static File? _wifiCsvFile;
  static File? _gpsCsvFile;
  static File? _btsCsvFile;
  static bool _wifiHeaderWritten = false;
  static bool _gpsHeaderWritten = false;
  static bool _btsHeaderWritten = false;

  /// مقداردهی اولیه فایل‌های CSV
  static Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();

      // WiFi CSV
      final wifiFilePath = '${directory.path}/$_wifiCsvFileName';
      _wifiCsvFile = File(wifiFilePath);
      if (await _wifiCsvFile!.exists()) {
        final content = await _wifiCsvFile!.readAsString();
        _wifiHeaderWritten = content.isNotEmpty && content.contains('Timestamp');
      } else {
        await _writeWifiHeader();
        _wifiHeaderWritten = true;
      }

      // GPS CSV (جدید - جدا از BTS)
      final gpsFilePath = '${directory.path}/$_gpsCsvFileName';
      _gpsCsvFile = File(gpsFilePath);
      if (await _gpsCsvFile!.exists()) {
        final content = await _gpsCsvFile!.readAsString();
        _gpsHeaderWritten = content.isNotEmpty && content.contains('Timestamp');
      } else {
        await _writeGpsHeader();
        _gpsHeaderWritten = true;
      }

      // BTS CSV (جدید - جدا از GPS)
      final btsFilePath = '${directory.path}/$_btsCsvFileName';
      _btsCsvFile = File(btsFilePath);
      if (await _btsCsvFile!.exists()) {
        final content = await _btsCsvFile!.readAsString();
        _btsHeaderWritten = content.isNotEmpty && content.contains('Timestamp');
      } else {
        await _writeBtsHeader();
        _btsHeaderWritten = true;
      }

      debugPrint('AutoCsvService initialized: WiFi=$wifiFilePath, GPS=$gpsFilePath, BTS=$btsFilePath');
    } catch (e) {
      debugPrint('Error initializing auto CSV service: $e');
    }
  }

  /// نوشتن header در فایل WiFi CSV
  static Future<void> _writeWifiHeader() async {
    if (_wifiCsvFile == null) return;

    final header = [
      'Timestamp',
      'Date',
      'Time',
      'Device ID (Hashed MAC)',
      // KNN
      'KNN Latitude',
      'KNN Longitude',
      'KNN Confidence',
      'Is Reliable',
      // Wi-Fi
      'WiFi BSSID',
      'WiFi RSSI (dBm)',
      'WiFi Frequency (MHz)',
      'WiFi SSID',
    ];

    final csvString = const ListToCsvConverter().convert([header]);
    await _wifiCsvFile!.writeAsString(csvString, mode: FileMode.write);
    debugPrint('WiFi CSV header written');
  }

  /// نوشتن header در فایل GPS CSV (جداگانه)
  static Future<void> _writeGpsHeader() async {
    if (_gpsCsvFile == null) return;

    final header = [
      'Timestamp',
      'Date',
      'Time',
      'Device ID (Hashed MAC)',
      // GPS
      'GPS Latitude',
      'GPS Longitude',
      'GPS Altitude (m)',
      'GPS Accuracy (m)',
      'GPS Speed (m/s)',
      'GPS Bearing',
    ];

    final csvString = const ListToCsvConverter().convert([header]);
    await _gpsCsvFile!.writeAsString(csvString, mode: FileMode.write);
    debugPrint('GPS CSV header written');
  }

  /// نوشتن header در فایل BTS CSV (جداگانه)
  static Future<void> _writeBtsHeader() async {
    if (_btsCsvFile == null) return;

    final header = [
      'Timestamp',
      'Date',
      'Time',
      'Device ID (Hashed MAC)',
      // مختصات مرجع (از KNN یا GPS)
      'Reference Latitude',
      'Reference Longitude',
      'Reference Zone',
      // BTS - فیلدهای دقیق
      'BTS Cell ID',
      'BTS LAC',
      'BTS TAC',
      'BTS MCC',
      'BTS MNC',
      'BTS Signal Strength (dBm)', // قدرت سیگنال - مهم‌ترین فیلد
      'BTS Network Type (RAT)',
      'BTS PCI',
      'BTS PSC',
      'BTS EARFCN',
      'BTS Serving',
    ];

    final csvString = const ListToCsvConverter().convert([header]);
    await _btsCsvFile!.writeAsString(csvString, mode: FileMode.write);
    debugPrint('BTS CSV header written');
  }

  /// ذخیره خودکار یک اسکن Wi-Fi + BTS + GPS در سه فایل CSV جداگانه
  static Future<void> saveScanToCsv({
    required WifiScanResult scanResult,
    CellScanResult? cellScanResult,
    Position? gpsPosition,
    LocationEstimate? knnEstimate,
    bool? isReliable,
    bool? isNewLocation,
    double? gpsKnnDistance,
    double? referenceLatitude,
    double? referenceLongitude,
    String? referenceZone,
  }) async {
    try {
      // اطمینان از اینکه فایل‌های CSV آماده هستند
      if (_wifiCsvFile == null || _gpsCsvFile == null || _btsCsvFile == null) {
        await initialize();
      }

      final timestamp = scanResult.timestamp;
      final date = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
      final deviceId = scanResult.deviceId;

      // مختصات مرجع (اولویت با KNN، سپس GPS، سپس پارامترهای ورودی)
      final refLat = knnEstimate?.latitude ?? gpsPosition?.latitude ?? referenceLatitude ?? 0.0;
      final refLon = knnEstimate?.longitude ?? gpsPosition?.longitude ?? referenceLongitude ?? 0.0;
      final refZone = referenceZone ?? knnEstimate?.zoneLabel ?? '';

      // ===== 1. ذخیره WiFi در wifi_scans_auto.csv =====
      if (_wifiCsvFile != null) {
        final wifiPrefix = [
          timestamp.toIso8601String(),
          date,
          time,
          deviceId,
          knnEstimate?.latitude ?? '',
          knnEstimate?.longitude ?? '',
          knnEstimate?.confidence ?? '',
          isReliable?.toString() ?? '',
        ];

        for (final ap in scanResult.accessPoints) {
          final row = [
            ...wifiPrefix,
            ap.bssid,
            ap.rssi,
            ap.frequency ?? '',
            ap.ssid ?? '',
          ];
          final csvString = const ListToCsvConverter().convert([row]);
          await _wifiCsvFile!.writeAsString('\n$csvString', mode: FileMode.append);
        }
        debugPrint('✓ WiFi CSV saved: ${scanResult.accessPoints.length} APs');
      }

      // ===== 2. ذخیره GPS در gps_scans_auto.csv (جداگانه) =====
      if (_gpsCsvFile != null && gpsPosition != null) {
        final row = [
          timestamp.toIso8601String(),
          date,
          time,
          deviceId,
          gpsPosition.latitude,
          gpsPosition.longitude,
          gpsPosition.altitude ?? '',
          gpsPosition.accuracy ?? '',
          gpsPosition.speed ?? '',
          gpsPosition.heading ?? '',
        ];
        final csvString = const ListToCsvConverter().convert([row]);
        await _gpsCsvFile!.writeAsString('\n$csvString', mode: FileMode.append);
        debugPrint('✓ GPS CSV saved: ${gpsPosition.latitude}, ${gpsPosition.longitude}');
      }

      // ===== 3. ذخیره BTS در bts_scans_auto.csv (جداگانه) =====
      if (_btsCsvFile != null && cellScanResult != null && cellScanResult.allCells.isNotEmpty) {
        final btsPrefix = [
          timestamp.toIso8601String(),
          date,
          time,
          deviceId,
          refLat,
          refLon,
          refZone,
        ];

        for (final cell in cellScanResult.allCells) {
          final isServing = cellScanResult.servingCell != null &&
              cell.uniqueId == cellScanResult.servingCell!.uniqueId;
          final row = [
            ...btsPrefix,
            cell.cellId ?? '',
            cell.lac ?? '',
            cell.tac ?? '',
            cell.mcc ?? '',
            cell.mnc ?? '',
            cell.signalStrength ?? '', // قدرت سیگنال - مهم‌ترین فیلد
            cell.networkType ?? '', // RAT
            cell.pci ?? '',
            cell.psc ?? '',
            cell.earfcn ?? '',
            isServing ? 'true' : 'false',
          ];
          final csvString = const ListToCsvConverter().convert([row]);
          await _btsCsvFile!.writeAsString('\n$csvString', mode: FileMode.append);
        }
        debugPrint('✓ BTS CSV saved: ${cellScanResult.allCells.length} cells');
      }
    } catch (e) {
      debugPrint('❌ Error saving scan to CSV: $e');
    }
  }

  // ===== مسیر فایل‌ها =====

  /// دریافت مسیر فایل WiFi CSV
  static Future<String?> getWifiCsvFilePath() async {
    if (_wifiCsvFile == null) {
      await initialize();
    }
    return _wifiCsvFile?.path;
  }

  /// دریافت مسیر فایل GPS CSV
  static Future<String?> getGpsCsvFilePath() async {
    if (_gpsCsvFile == null) {
      await initialize();
    }
    return _gpsCsvFile?.path;
  }

  /// دریافت مسیر فایل BTS CSV
  static Future<String?> getBtsCsvFilePath() async {
    if (_btsCsvFile == null) {
      await initialize();
    }
    return _btsCsvFile?.path;
  }

  /// دریافت مسیر فایل CSV (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<String?> getCsvFilePath() async {
    return await getWifiCsvFilePath();
  }

  // ===== اندازه فایل‌ها =====

  /// دریافت اندازه فایل WiFi CSV (به بایت)
  static Future<int?> getWifiCsvFileSize() async {
    if (_wifiCsvFile == null) {
      await initialize();
    }
    if (_wifiCsvFile != null && await _wifiCsvFile!.exists()) {
      return await _wifiCsvFile!.length();
    }
    return null;
  }

  /// دریافت اندازه فایل GPS CSV (به بایت)
  static Future<int?> getGpsCsvFileSize() async {
    if (_gpsCsvFile == null) {
      await initialize();
    }
    if (_gpsCsvFile != null && await _gpsCsvFile!.exists()) {
      return await _gpsCsvFile!.length();
    }
    return null;
  }

  /// دریافت اندازه فایل BTS CSV (به بایت)
  static Future<int?> getBtsCsvFileSize() async {
    if (_btsCsvFile == null) {
      await initialize();
    }
    if (_btsCsvFile != null && await _btsCsvFile!.exists()) {
      return await _btsCsvFile!.length();
    }
    return null;
  }

  /// دریافت اندازه فایل CSV (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<int?> getCsvFileSize() async {
    return await getWifiCsvFileSize();
  }

  // ===== تعداد ردیف‌ها =====

  /// دریافت تعداد ردیف‌های WiFi CSV (بدون header)
  static Future<int> getWifiCsvRowCount() async {
    if (_wifiCsvFile == null || !await _wifiCsvFile!.exists()) {
      return 0;
    }

    try {
      final content = await _wifiCsvFile!.readAsString();
      final lines = content.split('\n');
      return math.max(0, lines.length - 2);
    } catch (e) {
      debugPrint('Error counting WiFi CSV rows: $e');
      return 0;
    }
  }

  /// دریافت تعداد ردیف‌های GPS CSV (بدون header)
  static Future<int> getGpsCsvRowCount() async {
    if (_gpsCsvFile == null || !await _gpsCsvFile!.exists()) {
      return 0;
    }

    try {
      final content = await _gpsCsvFile!.readAsString();
      final lines = content.split('\n');
      return math.max(0, lines.length - 2);
    } catch (e) {
      debugPrint('Error counting GPS CSV rows: $e');
      return 0;
    }
  }

  /// دریافت تعداد ردیف‌های BTS CSV (بدون header)
  static Future<int> getBtsCsvRowCount() async {
    if (_btsCsvFile == null || !await _btsCsvFile!.exists()) {
      return 0;
    }

    try {
      final content = await _btsCsvFile!.readAsString();
      final lines = content.split('\n');
      return math.max(0, lines.length - 2);
    } catch (e) {
      debugPrint('Error counting BTS CSV rows: $e');
      return 0;
    }
  }

  /// دریافت تعداد ردیف‌های CSV (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<int> getCsvRowCount() async {
    return await getWifiCsvRowCount();
  }

  // ===== پاک کردن =====

  /// پاک کردن فایل‌های CSV (در صورت نیاز)
  static Future<void> clearCsv() async {
    if (_wifiCsvFile != null && await _wifiCsvFile!.exists()) {
      await _wifiCsvFile!.delete();
    }
    if (_gpsCsvFile != null && await _gpsCsvFile!.exists()) {
      await _gpsCsvFile!.delete();
    }
    if (_btsCsvFile != null && await _btsCsvFile!.exists()) {
      await _btsCsvFile!.delete();
    }
    _wifiHeaderWritten = false;
    _gpsHeaderWritten = false;
    _btsHeaderWritten = false;
    await initialize();
  }

  // ===== دانلود و اشتراک‌گذاری =====

  /// ذخیره فایل WiFi CSV در فولدر Download گوشی و بازکردن آن
  static Future<String?> saveWifiCsvToDownloadsAndOpen({String fileName = 'wifi_scans.csv'}) async {
    if (_wifiCsvFile == null) await initialize();
    if (_wifiCsvFile == null) return null;
    final csvContent = await _wifiCsvFile!.readAsString();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final outFile = File('${directory.path}/$fileName');
      await outFile.writeAsString(csvContent, flush: true);
      debugPrint('WiFi CSV saved to app documents: ${outFile.path}');

      try {
        await OpenFile.open(outFile.path);
      } catch (_) {}

      return outFile.path;
    } catch (e) {
      debugPrint('Error saving WiFi CSV to downloads: $e');
      return null;
    }
  }

  /// ذخیره فایل GPS/BTS CSV در فولدر Download گوشی و بازکردن آن
  static Future<String?> saveGpsBtsCsvToDownloadsAndOpen({String fileName = 'gps_bts_scans.csv'}) async {
    if (_gpsCsvFile == null) await initialize();
    if (_gpsCsvFile == null) return null;
    final csvContent = await _gpsCsvFile!.readAsString();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final outFile = File('${directory.path}/$fileName');
      await outFile.writeAsString(csvContent, flush: true);
      debugPrint('GPS/BTS CSV saved to app documents: ${outFile.path}');

      try {
        await OpenFile.open(outFile.path);
      } catch (_) {}

      return outFile.path;
    } catch (e) {
      debugPrint('Error saving GPS/BTS CSV to downloads: $e');
      return null;
    }
  }

  /// ذخیره فایل BTS CSV در فولدر Download گوشی و بازکردن آن
  static Future<String?> saveBtsCsvToDownloadsAndOpen({String fileName = 'bts_scans.csv'}) async {
    if (_btsCsvFile == null) await initialize();
    if (_btsCsvFile == null) return null;
    final csvContent = await _btsCsvFile!.readAsString();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final outFile = File('${directory.path}/$fileName');
      await outFile.writeAsString(csvContent, flush: true);
      debugPrint('BTS CSV saved to app documents: ${outFile.path}');

      try {
        await OpenFile.open(outFile.path);
      } catch (_) {}

      return outFile.path;
    } catch (e) {
      debugPrint('Error saving BTS CSV to downloads: $e');
      return null;
    }
  }

  /// ذخیره فایل CSV فعلی در فولدر Download گوشی و بازکردن آن (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<String?> saveCsvToDownloadsAndOpen({String fileName = 'wifi_knn_auto.csv'}) async {
    return await saveWifiCsvToDownloadsAndOpen(fileName: fileName);
  }

  /// افزودن اسکن به CSV (برای استفاده در Map Reference Point Picker)
  static Future<void> addScan({
    required WifiScanResult scanResult,
    CellScanResult? cellScanResult,
    Position? gpsPosition,
    required double latitude,
    required double longitude,
    String? zoneLabel,
  }) async {
    await saveScanToCsv(
      scanResult: scanResult,
      cellScanResult: cellScanResult,
      gpsPosition: gpsPosition,
      knnEstimate: null,
      isReliable: null,
      isNewLocation: null,
      gpsKnnDistance: null,
      referenceLatitude: latitude,
      referenceLongitude: longitude,
      referenceZone: zoneLabel,
    );
  }
}