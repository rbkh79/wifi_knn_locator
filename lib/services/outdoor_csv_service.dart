import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'outdoor_gps_bts_service.dart';
import 'outdoor_imu_service.dart';

/// سرویس ذخیره و export داده‌های Outdoor به CSV
/// 
/// این سرویس داده‌های GPS+BTS و IMU را در فایل‌های CSV جداگانه ذخیره می‌کند
class OutdoorCsvService {
  /// ذخیره رکوردهای GPS+BTS در CSV
  static Future<String?> saveGpsBtsRecords(List<OutdoorGpsBtsRecord> records) async {
    debugPrint('[DEBUG] ===== Saving GPS+BTS Records to CSV =====');
    debugPrint('[DEBUG] Number of records to save: ${records.length}');
    if (records.isEmpty) {
      debugPrint('[DEBUG] No GPS+BTS records to save');
      return null;
    }

    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'outdoor_gps_bts_$timestamp.csv';
      debugPrint('[DEBUG] Filename: $fileName');
      
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      debugPrint('[DEBUG] File path: ${file.path}');

      // ساخت CSV
      final csvData = <List<dynamic>>[];
      csvData.add(OutdoorGpsBtsRecord.csvHeader);
      debugPrint('[DEBUG] CSV Header: ${OutdoorGpsBtsRecord.csvHeader}');
      
      for (int i = 0; i < records.length; i++) {
        final record = records[i];
        csvData.add(record.toCsvRow());
        if (i < 3 || i == records.length - 1) {
          debugPrint('[DEBUG] Record ${i + 1}: ${record.toCsvRow()}');
        }
      }

      final csvString = const ListToCsvConverter().convert(csvData);
      debugPrint('[DEBUG] CSV string length: ${csvString.length} characters');
      debugPrint('[DEBUG] Writing to file...');
      await file.writeAsString(csvString);
      debugPrint('[DEBUG] File written successfully');

      debugPrint('[DEBUG] GPS+BTS CSV saved to: ${file.path}');
      debugPrint('[DEBUG] ===== CSV Save Complete =====');
      return file.path;
    } catch (e) {
      debugPrint('[DEBUG] Error saving GPS+BTS CSV: $e');
      debugPrint('[DEBUG] Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// ذخیره رکوردهای IMU در CSV
  static Future<String?> saveImuRecords(List<OutdoorImuRecord> records) async {
    if (records.isEmpty) {
      debugPrint('No IMU records to save');
      return null;
    }

    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'outdoor_imu_$timestamp.csv';
      
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');

      // ساخت CSV
      final csvData = <List<dynamic>>[];
      csvData.add(OutdoorImuRecord.csvHeader);
      
      for (final record in records) {
        csvData.add(record.toCsvRow());
      }

      final csvString = const ListToCsvConverter().convert(csvData);
      await file.writeAsString(csvString);

      debugPrint('IMU CSV saved to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('Error saving IMU CSV: $e');
      return null;
    }
  }

  /// دریافت لیست فایل‌های GPS+BTS CSV
  static Future<List<File>> getGpsBtsCsvFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync()
          .whereType<File>()
          .where((file) => file.path.contains('outdoor_gps_bts_') && file.path.endsWith('.csv'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())); // جدیدترین اول
      
      return files;
    } catch (e) {
      debugPrint('Error getting GPS+BTS CSV files: $e');
      return [];
    }
  }

  /// دریافت لیست فایل‌های IMU CSV
  static Future<List<File>> getImuCsvFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync()
          .whereType<File>()
          .where((file) => file.path.contains('outdoor_imu_') && file.path.endsWith('.csv'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())); // جدیدترین اول
      
      return files;
    } catch (e) {
      debugPrint('Error getting IMU CSV files: $e');
      return [];
    }
  }

  /// Export و باز کردن فایل GPS+BTS CSV
  static Future<void> exportAndOpenGpsBtsCsv() async {
    try {
      final files = await getGpsBtsCsvFiles();
      if (files.isEmpty) {
        debugPrint('No GPS+BTS CSV files to export');
        return;
      }

      // جدیدترین فایل
      final latestFile = files.first;
      
      // کپی به پوشه Documents با نام ساده‌تر
      final directory = await getApplicationDocumentsDirectory();
      final exportFileName = 'outdoor_gps_bts_export.csv';
      final exportFile = File('${directory.path}/$exportFileName');
      
      await latestFile.copy(exportFile.path);
      
      // باز کردن فایل
      await OpenFile.open(exportFile.path);
      
      debugPrint('GPS+BTS CSV exported and opened: ${exportFile.path}');
    } catch (e) {
      debugPrint('Error exporting GPS+BTS CSV: $e');
    }
  }

  /// Export و باز کردن فایل IMU CSV
  static Future<void> exportAndOpenImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to export');
        return;
      }

      // جدیدترین فایل
      final latestFile = files.first;
      
      // کپی به پوشه Documents با نام ساده‌تر
      final directory = await getApplicationDocumentsDirectory();
      final exportFileName = 'outdoor_imu_export.csv';
      final exportFile = File('${directory.path}/$exportFileName');
      
      await latestFile.copy(exportFile.path);
      
      // باز کردن فایل
      await OpenFile.open(exportFile.path);
      
      debugPrint('IMU CSV exported and opened: ${exportFile.path}');
    } catch (e) {
      debugPrint('Error exporting IMU CSV: $e');
    }
  }

  /// Share فایل GPS+BTS CSV
  static Future<void> shareGpsBtsCsv() async {
    try {
      final files = await getGpsBtsCsvFiles();
      if (files.isEmpty) {
        debugPrint('No GPS+BTS CSV files to share');
        return;
      }

      final latestFile = files.first;
      await Share.shareXFiles([XFile(latestFile.path)], text: 'Outdoor GPS+BTS Dataset');
      
      debugPrint('GPS+BTS CSV shared: ${latestFile.path}');
    } catch (e) {
      debugPrint('Error sharing GPS+BTS CSV: $e');
    }
  }

  /// Share فایل IMU CSV
  static Future<void> shareImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to share');
        return;
      }

      final latestFile = files.first;
      await Share.shareXFiles([XFile(latestFile.path)], text: 'Outdoor IMU Dataset');
      
      debugPrint('IMU CSV shared: ${latestFile.path}');
    } catch (e) {
      debugPrint('Error sharing IMU CSV: $e');
    }
  }

  /// پاک کردن تمام فایل‌های Outdoor CSV
  static Future<void> clearAllOutdoorCsvFiles() async {
    try {
      final gpsBtsFiles = await getGpsBtsCsvFiles();
      final imuFiles = await getImuCsvFiles();
      
      for (final file in [...gpsBtsFiles, ...imuFiles]) {
        await file.delete();
      }
      
      debugPrint('Cleared ${gpsBtsFiles.length + imuFiles.length} outdoor CSV files');
    } catch (e) {
      debugPrint('Error clearing outdoor CSV files: $e');
    }
  }

  /// دریافت آمار فایل‌های Outdoor
  static Future<Map<String, dynamic>> getOutdoorStatistics() async {
    try {
      final gpsBtsFiles = await getGpsBtsCsvFiles();
      final imuFiles = await getImuCsvFiles();

      int totalGpsBtsRecords = 0;
      int totalImuRecords = 0;

      // شمارش رکوردهای GPS+BTS
      for (final file in gpsBtsFiles) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        // منهای header و خط خالی آخر
        totalGpsBtsRecords += lines.length - 2;
      }

      // شمارش رکوردهای IMU
      for (final file in imuFiles) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        // منهای header و خط خالی آخر
        totalImuRecords += lines.length - 2;
      }

      return {
        'gps_bts_file_count': gpsBtsFiles.length,
        'imu_file_count': imuFiles.length,
        'total_gps_bts_records': totalGpsBtsRecords,
        'total_imu_records': totalImuRecords,
        'latest_gps_bts_file': gpsBtsFiles.isNotEmpty ? gpsBtsFiles.first.path : null,
        'latest_imu_file': imuFiles.isNotEmpty ? imuFiles.first.path : null,
      };
    } catch (e) {
      debugPrint('Error getting outdoor statistics: $e');
      return {};
    }
  }
}
