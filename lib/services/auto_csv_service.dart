import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import '../data_model.dart';
import 'package:open_file/open_file.dart';

/// سرویس ذخیره خودکار CSV در هر اسکن Wi-Fi و BTS
class AutoCsvService {
  static const String _wifiCsvFileName = 'wifi_scans_auto.csv';
  static const String _gpsBtsCsvFileName = 'gps_bts_scans_auto.csv';
  static File? _wifiCsvFile;
  static File? _gpsBtsCsvFile;
  static bool _wifiHeaderWritten = false;
  static bool _gpsBtsHeaderWritten = false;

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

      // GPS/BTS CSV
      final gpsBtsFilePath = '${directory.path}/$_gpsBtsCsvFileName';
      _gpsBtsCsvFile = File(gpsBtsFilePath);
      if (await _gpsBtsCsvFile!.exists()) {
        final content = await _gpsBtsCsvFile!.readAsString();
        _gpsBtsHeaderWritten = content.isNotEmpty && content.contains('Timestamp');
      } else {
        await _writeGpsBtsHeader();
        _gpsBtsHeaderWritten = true;
      }

      debugPrint('AutoCsvService initialized: WiFi=$wifiFilePath, GPS/BTS=$gpsBtsFilePath');
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

  /// نوشتن header در فایل GPS/BTS CSV
  static Future<void> _writeGpsBtsHeader() async {
    if (_gpsBtsCsvFile == null) return;

    final header = [
      'Timestamp',
      'Date',
      'Time',
      'Device ID (Hashed MAC)',
      // GPS
      'GPS Latitude',
      'GPS Longitude',
      'GPS Accuracy (m)',
      // BTS
      'BTS Cell ID',
      'BTS LAC',
      'BTS TAC',
      'BTS MCC',
      'BTS MNC',
      'BTS Signal (dBm)',
      'BTS Network Type',
      'BTS PCI',
      'BTS Serving',
    ];

    final csvString = const ListToCsvConverter().convert([header]);
    await _gpsBtsCsvFile!.writeAsString(csvString, mode: FileMode.write);
    debugPrint('GPS/BTS CSV header written');
  }

  /// ذخیره خودکار یک اسکن Wi-Fi + BTS در دو فایل CSV جداگانه
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
      if (_wifiCsvFile == null || _gpsBtsCsvFile == null) {
        await initialize();
      }

      final timestamp = scanResult.timestamp;
      final date = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
      final deviceId = scanResult.deviceId;

      // ===== ذخیره WiFi در wifi_scans_auto.csv =====
      if (_wifiCsvFile != null) {
        // ستون‌های WiFi
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
            referenceZone ?? ap.ssid ?? '',
          ];
          final csvString = const ListToCsvConverter().convert([row]);
          await _wifiCsvFile!.writeAsString('\n$csvString', mode: FileMode.append);
        }
        debugPrint('✓ WiFi CSV saved: ${scanResult.accessPoints.length} APs');
      }

      // ===== ذخیره GPS و BTS در gps_bts_scans_auto.csv =====
      if (_gpsBtsCsvFile != null) {
        // ستون‌های GPS/BTS
        final gpsBtsPrefix = [
          timestamp.toIso8601String(),
          date,
          time,
          deviceId,
          gpsPosition?.latitude ?? 'ERROR',
          gpsPosition?.longitude ?? 'ERROR',
          gpsPosition?.accuracy ?? 'ERROR',
        ];

        // ردیف‌های BTS
        if (cellScanResult != null && cellScanResult.allCells.isNotEmpty) {
          for (final cell in cellScanResult.allCells) {
            final isServing = cellScanResult.servingCell != null &&
                cell.uniqueId == cellScanResult.servingCell!.uniqueId;
            final row = [
              ...gpsBtsPrefix,
              cell.cellId ?? '',
              cell.lac ?? '',
              cell.tac ?? '',
              cell.mcc ?? '',
              cell.mnc ?? '',
              cell.signalStrength ?? '',
              cell.networkType ?? '',
              cell.pci ?? '',
              isServing ? 'true' : 'false',
            ];
            final csvString = const ListToCsvConverter().convert([row]);
            await _gpsBtsCsvFile!.writeAsString('\n$csvString', mode: FileMode.append);
          }
          debugPrint('✓ GPS/BTS CSV saved: ${cellScanResult.allCells.length} cells, GPS=${gpsPosition != null}');
        } else {
          // اگر BTS خالی باشد، فقط GPS را ذخیره کن
          final row = [
            ...gpsBtsPrefix,
            '', '', '', '', '', '', '', '', '', // BTS columns empty
          ];
          final csvString = const ListToCsvConverter().convert([row]);
          await _gpsBtsCsvFile!.writeAsString('\n$csvString', mode: FileMode.append);
          debugPrint('✓ GPS/BTS CSV saved: GPS only (BTS empty)');
        }
      }
    } catch (e) {
      debugPrint('❌ Error saving scan to CSV: $e');
    }
  }

  /// دریافت مسیر فایل WiFi CSV
  static Future<String?> getWifiCsvFilePath() async {
    if (_wifiCsvFile == null) {
      await initialize();
    }
    return _wifiCsvFile?.path;
  }

  /// دریافت مسیر فایل GPS/BTS CSV
  static Future<String?> getGpsBtsCsvFilePath() async {
    if (_gpsBtsCsvFile == null) {
      await initialize();
    }
    return _gpsBtsCsvFile?.path;
  }

  /// دریافت مسیر فایل CSV (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<String?> getCsvFilePath() async {
    return await getWifiCsvFilePath();
  }

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

  /// دریافت اندازه فایل GPS/BTS CSV (به بایت)
  static Future<int?> getGpsBtsCsvFileSize() async {
    if (_gpsBtsCsvFile == null) {
      await initialize();
    }
    if (_gpsBtsCsvFile != null && await _gpsBtsCsvFile!.exists()) {
      return await _gpsBtsCsvFile!.length();
    }
    return null;
  }

  /// دریافت اندازه فایل CSV (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<int?> getCsvFileSize() async {
    return await getWifiCsvFileSize();
  }

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

  /// دریافت تعداد ردیف‌های GPS/BTS CSV (بدون header)
  static Future<int> getGpsBtsCsvRowCount() async {
    if (_gpsBtsCsvFile == null || !await _gpsBtsCsvFile!.exists()) {
      return 0;
    }

    try {
      final content = await _gpsBtsCsvFile!.readAsString();
      final lines = content.split('\n');
      return math.max(0, lines.length - 2);
    } catch (e) {
      debugPrint('Error counting GPS/BTS CSV rows: $e');
      return 0;
    }
  }

  /// دریافت تعداد ردیف‌های CSV (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<int> getCsvRowCount() async {
    return await getWifiCsvRowCount();
  }

  /// پاک کردن فایل‌های CSV (در صورت نیاز)
  static Future<void> clearCsv() async {
    if (_wifiCsvFile != null && await _wifiCsvFile!.exists()) {
      await _wifiCsvFile!.delete();
    }
    if (_gpsBtsCsvFile != null && await _gpsBtsCsvFile!.exists()) {
      await _gpsBtsCsvFile!.delete();
    }
    _wifiHeaderWritten = false;
    _gpsBtsHeaderWritten = false;
    await initialize();
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
    if (_gpsBtsCsvFile == null) await initialize();
    if (_gpsBtsCsvFile == null) return null;
    final csvContent = await _gpsBtsCsvFile!.readAsString();

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

  /// ذخیره فایل CSV فعلی در فولدر Download گوشی و بازکردن آن (برای سازگاری با قدیم - WiFi را برمی‌گرداند)
  static Future<String?> saveCsvToDownloadsAndOpen({String fileName = 'wifi_knn_auto.csv'}) async {
    return await saveWifiCsvToDownloadsAndOpen(fileName: fileName);
  }
}
