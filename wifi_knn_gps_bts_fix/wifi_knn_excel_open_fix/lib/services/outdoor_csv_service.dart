import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart';
import 'outdoor_gps_bts_service.dart';
import 'outdoor_imu_service.dart';

/// Stores Outdoor GPS+BTS and IMU sessions as CSV.
///
/// Researcher Mode keeps CSV as the archival format, but when the user taps
/// Export it creates a real .xlsx workbook and opens it with an Android app
/// that can handle Excel files. The export path never calls Share.shareXFiles.
class OutdoorCsvService {
  static const String _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Save GPS+BTS records as CSV.
  static Future<String?> saveGpsBtsRecords(
    List<OutdoorGpsBtsRecord> records,
  ) async {
    debugPrint('[DEBUG] ===== Saving GPS+BTS Records to CSV =====');
    debugPrint('[DEBUG] Number of records to save: ${records.length}');
    if (records.isEmpty) {
      debugPrint('[DEBUG] No GPS+BTS records to save');
      return null;
    }

    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'outdoor_gps_bts_$timestamp.csv';
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');

      final csvData = <List<dynamic>>[
        OutdoorGpsBtsRecord.csvHeader,
        ...records.map((record) => record.toCsvRow()),
      ];

      final csvString = const ListToCsvConverter().convert(csvData);
      await file.writeAsString(csvString, flush: true);

      debugPrint('[DEBUG] GPS+BTS CSV saved to: ${file.path}');
      return file.path;
    } catch (e, st) {
      debugPrint('[DEBUG] Error saving GPS+BTS CSV: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Save IMU records as CSV.
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

      final csvData = <List<dynamic>>[
        OutdoorImuRecord.csvHeader,
        ...records.map((record) => record.toCsvRow()),
      ];

      final csvString = const ListToCsvConverter().convert(csvData);
      await file.writeAsString(csvString, flush: true);

      debugPrint('IMU CSV saved to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('Error saving IMU CSV: $e');
      return null;
    }
  }

  /// Get GPS+BTS CSV files, newest first.
  static Future<List<File>> getGpsBtsCsvFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.contains('outdoor_gps_bts_') &&
                file.path.endsWith('.csv'),
          )
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
      return files;
    } catch (e) {
      debugPrint('Error getting GPS+BTS CSV files: $e');
      return [];
    }
  }

  /// Get IMU CSV files, newest first.
  static Future<List<File>> getImuCsvFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.contains('outdoor_imu_') &&
                file.path.endsWith('.csv'),
          )
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
      return files;
    } catch (e) {
      debugPrint('Error getting IMU CSV files: $e');
      return [];
    }
  }

  /// Convert a CSV file to a real XLSX workbook.
  ///
  /// Values are intentionally stored as text. This prevents Excel from
  /// silently changing large Cell IDs/eNodeB IDs to scientific notation or
  /// losing digits.
  static Future<File> _csvToXlsx({
    required File csvFile,
    required String xlsxFileName,
    required String sheetName,
  }) async {
    final csvContent = await csvFile.readAsString();
    final rows = const CsvToListConverter().convert(csvContent);

    final excel = Excel.createExcel();
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    for (final row in rows) {
      sheet.appendRow(
        row
            .map<CellValue>(
              (value) => TextCellValue(value?.toString() ?? ''),
            )
            .toList(),
      );
    }

    final bytes = excel.save();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel package returned empty XLSX bytes');
    }

    final directory = await getApplicationDocumentsDirectory();
    final xlsxFile = File('${directory.path}/$xlsxFileName');
    await xlsxFile.writeAsBytes(bytes, flush: true);
    return xlsxFile;
  }

  /// Export the newest Outdoor GPS+BTS session as XLSX and open it.
  ///
  /// Kept with the old method name so main.dart does not need a functional
  /// change. This method DOES NOT open the Android share sheet.
  static Future<void> exportAndOpenGpsBtsCsv() async {
    try {
      final files = await getGpsBtsCsvFiles();
      if (files.isEmpty) {
        debugPrint('No GPS+BTS CSV files to export');
        return;
      }

      final xlsxFile = await _csvToXlsx(
        csvFile: files.first,
        xlsxFileName: 'outdoor_gps_bts_export.xlsx',
        sheetName: 'GPS_BTS',
      );

      final result = await OpenFile.open(
        xlsxFile.path,
        type: _xlsxMime,
      );

      debugPrint(
        'GPS+BTS XLSX open result: type=${result.type}, '
        'message=${result.message}, path=${xlsxFile.path}',
      );
    } catch (e, st) {
      debugPrint('Error exporting/opening GPS+BTS XLSX: $e');
      debugPrint('$st');
    }
  }

  /// Export the newest Outdoor IMU session as XLSX and open it.
  static Future<void> exportAndOpenImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to export');
        return;
      }

      final xlsxFile = await _csvToXlsx(
        csvFile: files.first,
        xlsxFileName: 'outdoor_imu_export.xlsx',
        sheetName: 'IMU_GPS',
      );

      final result = await OpenFile.open(
        xlsxFile.path,
        type: _xlsxMime,
      );

      debugPrint(
        'IMU XLSX open result: type=${result.type}, '
        'message=${result.message}, path=${xlsxFile.path}',
      );
    } catch (e, st) {
      debugPrint('Error exporting/opening IMU XLSX: $e');
      debugPrint('$st');
    }
  }

  /// Optional manual sharing function. Researcher Mode export buttons do not
  /// call this function.
  static Future<void> shareGpsBtsCsv() async {
    try {
      final files = await getGpsBtsCsvFiles();
      if (files.isEmpty) {
        debugPrint('No GPS+BTS CSV files to share');
        return;
      }
      final latestFile = files.first;
      await Share.shareXFiles(
        [XFile(latestFile.path)],
        text: 'Outdoor GPS+BTS Dataset',
      );
      debugPrint('GPS+BTS CSV shared: ${latestFile.path}');
    } catch (e) {
      debugPrint('Error sharing GPS+BTS CSV: $e');
    }
  }

  /// Optional manual sharing function. Researcher Mode export buttons do not
  /// call this function.
  static Future<void> shareImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to share');
        return;
      }
      final latestFile = files.first;
      await Share.shareXFiles(
        [XFile(latestFile.path)],
        text: 'Outdoor IMU Dataset',
      );
      debugPrint('IMU CSV shared: ${latestFile.path}');
    } catch (e) {
      debugPrint('Error sharing IMU CSV: $e');
    }
  }

  /// Delete Outdoor CSV session files.
  static Future<void> clearAllOutdoorCsvFiles() async {
    try {
      final gpsBtsFiles = await getGpsBtsCsvFiles();
      final imuFiles = await getImuCsvFiles();

      for (final file in [...gpsBtsFiles, ...imuFiles]) {
        await file.delete();
      }

      debugPrint(
        'Cleared ${gpsBtsFiles.length + imuFiles.length} outdoor CSV files',
      );
    } catch (e) {
      debugPrint('Error clearing outdoor CSV files: $e');
    }
  }

  /// Return Outdoor file statistics.
  static Future<Map<String, dynamic>> getOutdoorStatistics() async {
    try {
      final gpsBtsFiles = await getGpsBtsCsvFiles();
      final imuFiles = await getImuCsvFiles();

      int totalGpsBtsRecords = 0;
      int totalImuRecords = 0;

      for (final file in gpsBtsFiles) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        totalGpsBtsRecords += lines.length - 2;
      }

      for (final file in imuFiles) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        totalImuRecords += lines.length - 2;
      }

      return {
        'gps_bts_file_count': gpsBtsFiles.length,
        'imu_file_count': imuFiles.length,
        'total_gps_bts_records': totalGpsBtsRecords,
        'total_imu_records': totalImuRecords,
        'latest_gps_bts_file':
            gpsBtsFiles.isNotEmpty ? gpsBtsFiles.first.path : null,
        'latest_imu_file':
            imuFiles.isNotEmpty ? imuFiles.first.path : null,
      };
    } catch (e) {
      debugPrint('Error getting outdoor statistics: $e');
      return {};
    }
  }
}
