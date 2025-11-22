import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import '../data_model.dart';
import '../utils/privacy_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';

/// سرویس ذخیره خودکار CSV در هر اسکن Wi-Fi
class AutoCsvService {
  static const String _csvFileName = 'wifi_scans_auto.csv';
  static File? _csvFile;
  static bool _headerWritten = false;

  /// مقداردهی اولیه فایل CSV
  static Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$_csvFileName';
      _csvFile = File(filePath);

      // بررسی اینکه آیا فایل وجود دارد و header نوشته شده است
      if (await _csvFile!.exists()) {
        _headerWritten = true;
      } else {
        // نوشتن header در اولین بار
        await _writeHeader();
        _headerWritten = true;
      }
    } catch (e) {
      debugPrint('Error initializing auto CSV service: $e');
    }
  }

  /// نوشتن header در فایل CSV
  static Future<void> _writeHeader() async {
    if (_csvFile == null) return;

    final header = [
      'Timestamp',
      'Date',
      'Time',
      'Device ID (Hashed MAC)',
      'GPS Latitude',
      'GPS Longitude',
      'GPS Accuracy (m)',
      'KNN Latitude',
      'KNN Longitude',
      'KNN Confidence',
      'Distance GPS-KNN (m)',
      'Is Reliable',
      'Is New Location',
      'BSSID',
      'RSSI',
      'Frequency',
      'SSID',
    ];

    final csvString = const ListToCsvConverter().convert([header]);
    await _csvFile!.writeAsString(csvString, mode: FileMode.write);
  }

  /// ذخیره خودکار یک اسکن Wi-Fi در CSV
  /// 
  /// این متد در هر بار اسکن Wi-Fi فراخوانی می‌شود و اطلاعات را به CSV اضافه می‌کند
  static Future<void> saveScanToCsv({
    required WifiScanResult scanResult,
    Position? gpsPosition,
    LocationEstimate? knnEstimate,
    bool? isReliable,
    bool? isNewLocation,
    double? gpsKnnDistance,
  }) async {
    if (_csvFile == null) {
      await initialize();
    }

    if (_csvFile == null || !_headerWritten) {
      debugPrint('CSV file not initialized');
      return;
    }

    try {
      final timestamp = scanResult.timestamp;
      final date = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
      final deviceId = scanResult.deviceId;

      // اگر هیچ AP یافت نشده، یک ردیف خالی اضافه می‌کنیم
      if (scanResult.accessPoints.isEmpty) {
        final row = [
          timestamp.toIso8601String(),
          date,
          time,
          deviceId,
          gpsPosition?.latitude ?? '',
          gpsPosition?.longitude ?? '',
          gpsPosition?.accuracy ?? '',
          knnEstimate?.latitude ?? '',
          knnEstimate?.longitude ?? '',
          knnEstimate?.confidence ?? '',
          gpsKnnDistance ?? '',
          isReliable?.toString() ?? '',
          isNewLocation?.toString() ?? '',
          '', // BSSID
          '', // RSSI
          '', // Frequency
          '', // SSID
        ];

        final csvString = const ListToCsvConverter().convert([row]);
        await _csvFile!.writeAsString(csvString, mode: FileMode.append);
        return;
      }

      // برای هر AP یک ردیف اضافه می‌کنیم
      for (final ap in scanResult.accessPoints) {
        final row = [
          timestamp.toIso8601String(),
          date,
          time,
          deviceId,
          gpsPosition?.latitude ?? '',
          gpsPosition?.longitude ?? '',
          gpsPosition?.accuracy ?? '',
          knnEstimate?.latitude ?? '',
          knnEstimate?.longitude ?? '',
          knnEstimate?.confidence ?? '',
          gpsKnnDistance ?? '',
          isReliable?.toString() ?? '',
          isNewLocation?.toString() ?? '',
          ap.bssid,
          ap.rssi,
          ap.frequency ?? '',
          ap.ssid ?? '',
        ];

        final csvString = const ListToCsvConverter().convert([row]);
        await _csvFile!.writeAsString(csvString, mode: FileMode.append);
      }

      debugPrint('Scan saved to auto CSV: ${scanResult.accessPoints.length} APs');
    } catch (e) {
      debugPrint('Error saving scan to CSV: $e');
    }
  }

  /// دریافت مسیر فایل CSV
  static Future<String?> getCsvFilePath() async {
    if (_csvFile == null) {
      await initialize();
    }
    return _csvFile?.path;
  }

  /// دریافت اندازه فایل CSV (به بایت)
  static Future<int?> getCsvFileSize() async {
    if (_csvFile == null) {
      await initialize();
    }
    if (_csvFile != null && await _csvFile!.exists()) {
      return await _csvFile!.length();
    }
    return null;
  }

  /// دریافت تعداد ردیف‌های CSV (بدون header)
  static Future<int> getCsvRowCount() async {
    if (_csvFile == null || !await _csvFile!.exists()) {
      return 0;
    }

    try {
      final content = await _csvFile!.readAsString();
      final lines = content.split('\n');
      // -1 برای header، -1 برای خط خالی احتمالی آخر
      return math.max(0, lines.length - 2);
    } catch (e) {
      debugPrint('Error counting CSV rows: $e');
      return 0;
    }
  }

  /// پاک کردن فایل CSV (در صورت نیاز)
  static Future<void> clearCsv() async {
    if (_csvFile != null && await _csvFile!.exists()) {
      await _csvFile!.delete();
      _headerWritten = false;
      await initialize();
    }
  }

  /// افزودن اسکن به CSV (برای استفاده در Map Reference Point Picker)
  static Future<void> addScan({
    required WifiScanResult scanResult,
    required double latitude,
    required double longitude,
    String? zoneLabel,
  }) async {
    await saveScanToCsv(
      scanResult: scanResult,
      gpsPosition: null, // در این حالت GPS نداریم
      knnEstimate: null,
      isReliable: null,
      isNewLocation: null,
      gpsKnnDistance: null,
    );
  }

  /// ذخیره فایل CSV فعلی در فولدر Download گوشی و بازکردن آن
  static Future<String?> saveCsvToDownloadsAndOpen({String fileName = 'wifi_knn_auto.csv'}) async {
    // دریافت محتوا
    if (_csvFile == null) await initialize();
    if (_csvFile == null) return null;
    final csvContent = await _csvFile!.readAsString();

    // درخواست دسترسی
    if (!await Permission.storage.request().isGranted) {
      return null;
    }
    try {
      // مسیر پوشه دانلود اندروید
      final Directory downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        return null;
      }
      final outFile = File('${downloadsDir.path}/$fileName');
      await outFile.writeAsString(csvContent, flush: true);
      // بازکردن فایل با فایل‌منیجر یا اکسل
      await OpenFile.open(outFile.path);
      return outFile.path;
    } catch (e) {
      debugPrint('Error saving CSV to Downloads: $e');
      return null;
    }
  }
}

