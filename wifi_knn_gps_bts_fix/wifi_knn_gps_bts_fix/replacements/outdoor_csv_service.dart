import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'outdoor_gps_bts_service.dart';
import 'outdoor_imu_service.dart';

/// Durable storage/export service for Outdoor datasets.
///
/// GPS+BTS is write-through:
/// - session CSV is created before recording starts
/// - each record is appended and flushed immediately
/// - a final rewrite is performed on Stop
///
/// Researcher export creates a real XLSX file and opens Android's share/save UI.
class OutdoorCsvService {
  static const ListToCsvConverter _csvWriter = ListToCsvConverter();

  static String _safeTimestamp() {
    return DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }

  static Future<Directory> _documentsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Creates a GPS+BTS session file immediately, before the first sample.
  ///
  /// UTF-8 BOM is included so Excel opens CSV text reliably.
  static Future<String?> createGpsBtsSessionFile() async {
    try {
      final directory = await _documentsDirectory();
      final file = File(
        '${directory.path}/outdoor_gps_bts_${_safeTimestamp()}.csv',
      );

      final header = _csvWriter.convert(<List<dynamic>>[
        OutdoorGpsBtsRecord.csvHeader,
      ]);

      await file.writeAsString(
        '\uFEFF$header\n',
        mode: FileMode.write,
        flush: true,
      );

      debugPrint('[OutdoorCSV] Session created: ${file.path}');
      return file.path;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] Cannot create GPS+BTS session: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// Appends one row and flushes it to storage immediately.
  static Future<bool> appendGpsBtsRecord(
    String filePath,
    OutdoorGpsBtsRecord record,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final row = _csvWriter.convert(<List<dynamic>>[
        record.toCsvRow(),
      ]);

      await file.writeAsString(
        '$row\n',
        mode: FileMode.append,
        flush: true,
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] Append failed: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// Final consistency write using temp + backup so an existing valid session
  /// is not silently lost if a final rewrite fails.
  static Future<bool> rewriteGpsBtsSession(
    String filePath,
    List<OutdoorGpsBtsRecord> records,
  ) async {
    if (records.isEmpty) return false;

    final target = File(filePath);
    final temp = File('$filePath.tmp');
    final backup = File('$filePath.bak');

    try {
      final rows = <List<dynamic>>[
        OutdoorGpsBtsRecord.csvHeader,
        ...records.map((record) => record.toCsvRow()),
      ];
      final csv = _csvWriter.convert(rows);

      await temp.writeAsString(
        '\uFEFF$csv\n',
        mode: FileMode.write,
        flush: true,
      );

      if (await backup.exists()) {
        await backup.delete();
      }

      if (await target.exists()) {
        await target.rename(backup.path);
      }

      try {
        await temp.rename(target.path);
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }

      if (await backup.exists()) {
        await backup.delete();
      }

      debugPrint(
        '[OutdoorCSV] Finalized ${records.length} rows: ${target.path}',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] Rewrite failed: $e');
      debugPrint('$stackTrace');

      try {
        if (await temp.exists()) await temp.delete();
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
      } catch (_) {}

      return false;
    }
  }

  static Future<bool> gpsBtsFileExists(String filePath) async {
    try {
      return File(filePath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Backward-compatible full save.
  static Future<String?> saveGpsBtsRecords(
    List<OutdoorGpsBtsRecord> records,
  ) async {
    if (records.isEmpty) {
      debugPrint('[OutdoorCSV] No GPS+BTS records to save');
      return null;
    }

    final path = await createGpsBtsSessionFile();
    if (path == null) return null;

    final ok = await rewriteGpsBtsSession(path, records);
    return ok ? path : null;
  }

  /// Existing IMU save behavior retained.
  static Future<String?> saveImuRecords(
    List<OutdoorImuRecord> records,
  ) async {
    if (records.isEmpty) {
      debugPrint('No IMU records to save');
      return null;
    }

    try {
      final timestamp = _safeTimestamp();
      final fileName = 'outdoor_imu_$timestamp.csv';
      final directory = await _documentsDirectory();
      final file = File('${directory.path}/$fileName');

      final csvData = <List<dynamic>>[
        OutdoorImuRecord.csvHeader,
        ...records.map((record) => record.toCsvRow()),
      ];

      final csvString = _csvWriter.convert(csvData);
      await file.writeAsString(
        '\uFEFF$csvString\n',
        flush: true,
      );

      debugPrint('IMU CSV saved to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('Error saving IMU CSV: $e');
      return null;
    }
  }

  static String _fileName(File file) {
    return file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
  }

  /// All GPS+BTS session CSV files, newest first.
  /// Temporary/backup/export helper files are excluded.
  static Future<List<File>> getGpsBtsCsvFiles() async {
    try {
      final directory = await _documentsDirectory();
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) {
            final name = _fileName(file);
            return name.startsWith('outdoor_gps_bts_') &&
                name.endsWith('.csv') &&
                !name.contains('_export') &&
                !name.endsWith('.tmp') &&
                !name.endsWith('.bak');
          })
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

      return files;
    } catch (e) {
      debugPrint('Error getting GPS+BTS CSV files: $e');
      return <File>[];
    }
  }

  static Future<List<File>> getImuCsvFiles() async {
    try {
      final directory = await _documentsDirectory();
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) {
            final name = _fileName(file);
            return name.startsWith('outdoor_imu_') &&
                name.endsWith('.csv') &&
                !name.contains('_export');
          })
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

      return files;
    } catch (e) {
      debugPrint('Error getting IMU CSV files: $e');
      return <File>[];
    }
  }

  static Future<List<List<dynamic>>> _readCsvRows(File file) async {
    var content = await file.readAsString();
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    if (content.trim().isEmpty) {
      return <List<dynamic>>[];
    }

    return const CsvToListConverter(
      shouldParseNumbers: true,
    ).convert(content);
  }

  static Future<File?> _latestGpsBtsDataFile() async {
    final files = await getGpsBtsCsvFiles();

    for (final file in files) {
      try {
        final rows = await _readCsvRows(file);
        if (rows.length > 1) {
          return file;
        }
      } catch (_) {}
    }

    return null;
  }

  static CellValue _excelValue(dynamic value) {
    if (value == null || value == '') {
      return TextCellValue('');
    }
    if (value is bool) {
      return BoolCellValue(value);
    }
    if (value is int) {
      return IntCellValue(value);
    }
    if (value is double) {
      return DoubleCellValue(value);
    }
    if (value is num) {
      return DoubleCellValue(value.toDouble());
    }
    return TextCellValue(value.toString());
  }

  /// Creates a genuine .xlsx workbook from a durable GPS+BTS CSV.
  ///
  /// If [csvPath] is provided (for example immediately after Stop), that exact
  /// session is exported. Otherwise the newest non-empty session is used.
  static Future<String?> exportGpsBtsXlsx({
    String? csvPath,
  }) async {
    try {
      File? source;

      if (csvPath != null) {
        final candidate = File(csvPath);
        if (await candidate.exists()) {
          final rows = await _readCsvRows(candidate);
          if (rows.length > 1) {
            source = candidate;
          }
        }
      }

      source ??= await _latestGpsBtsDataFile();

      if (source == null) {
        debugPrint('[OutdoorCSV] No non-empty GPS+BTS session to export');
        return null;
      }

      final rows = await _readCsvRows(source);
      if (rows.length <= 1) {
        return null;
      }

      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();

      const sheetName = 'Outdoor_GPS_BTS';
      if (defaultSheet != null && defaultSheet != sheetName) {
        workbook.rename(defaultSheet, sheetName);
      }

      final sheet = workbook[sheetName];

      for (final row in rows) {
        sheet.appendRow(
          row.map<CellValue>((value) => _excelValue(value)).toList(),
        );
      }

      final bytes = workbook.save();
      if (bytes == null || bytes.isEmpty) {
        debugPrint('[OutdoorCSV] XLSX encoder returned no bytes');
        return null;
      }

      final directory = await _documentsDirectory();
      final xlsxFile = File(
        '${directory.path}/outdoor_gps_bts_export_${_safeTimestamp()}.xlsx',
      );

      await xlsxFile.writeAsBytes(bytes, flush: true);
      debugPrint('[OutdoorCSV] XLSX created: ${xlsxFile.path}');
      return xlsxFile.path;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] XLSX export failed: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// Preferred Researcher Mode export:
  /// creates a real XLSX and opens Android/iOS share-save UI.
  static Future<bool> shareGpsBtsXlsx({
    String? csvPath,
  }) async {
    try {
      final xlsxPath = await exportGpsBtsXlsx(csvPath: csvPath);
      if (xlsxPath == null) return false;

      await Share.shareXFiles(
        <XFile>[XFile(xlsxPath)],
        text: 'Outdoor GPS+BTS Dataset (XLSX)',
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] Share XLSX failed: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// CSV share fallback; useful even if the Excel package/export fails.
  static Future<bool> shareGpsBtsCsv({
    String? filePath,
  }) async {
    try {
      File? file;

      if (filePath != null) {
        final candidate = File(filePath);
        if (await candidate.exists()) {
          final rows = await _readCsvRows(candidate);
          if (rows.length > 1) {
            file = candidate;
          }
        }
      }

      file ??= await _latestGpsBtsDataFile();
      if (file == null) return false;

      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: 'Outdoor GPS+BTS Dataset (CSV)',
      );

      debugPrint('GPS+BTS CSV shared: ${file.path}');
      return true;
    } catch (e) {
      debugPrint('Error sharing GPS+BTS CSV: $e');
      return false;
    }
  }

  /// Backward-compatible button target.
  ///
  /// It now exports XLSX first, then falls back to sharing CSV. It no longer
  /// depends on a spreadsheet app being registered for OpenFile.
  static Future<void> exportAndOpenGpsBtsCsv() async {
    final xlsxShared = await shareGpsBtsXlsx();
    if (xlsxShared) return;

    final csvShared = await shareGpsBtsCsv();
    if (csvShared) return;

    debugPrint('No GPS+BTS dataset is available to export');
  }

  static Future<void> exportAndOpenImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to export');
        return;
      }

      final latestFile = files.first;
      final directory = await _documentsDirectory();
      final exportFile = File('${directory.path}/outdoor_imu_export.csv');

      await latestFile.copy(exportFile.path);
      await OpenFile.open(exportFile.path);

      debugPrint('IMU CSV exported and opened: ${exportFile.path}');
    } catch (e) {
      debugPrint('Error exporting IMU CSV: $e');
    }
  }

  static Future<void> shareImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to share');
        return;
      }

      final latestFile = files.first;
      await Share.shareXFiles(
        <XFile>[XFile(latestFile.path)],
        text: 'Outdoor IMU Dataset',
      );

      debugPrint('IMU CSV shared: ${latestFile.path}');
    } catch (e) {
      debugPrint('Error sharing IMU CSV: $e');
    }
  }

  static Future<void> clearAllOutdoorCsvFiles() async {
    try {
      final gpsBtsFiles = await getGpsBtsCsvFiles();
      final imuFiles = await getImuCsvFiles();

      for (final file in <File>[...gpsBtsFiles, ...imuFiles]) {
        await file.delete();
      }

      debugPrint(
        'Cleared ${gpsBtsFiles.length + imuFiles.length} outdoor CSV files',
      );
    } catch (e) {
      debugPrint('Error clearing outdoor CSV files: $e');
    }
  }

  static Future<int> _countDataRows(File file) async {
    try {
      final rows = await _readCsvRows(file);
      return rows.length > 1 ? rows.length - 1 : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<Map<String, dynamic>> getOutdoorStatistics() async {
    try {
      final gpsBtsFiles = await getGpsBtsCsvFiles();
      final imuFiles = await getImuCsvFiles();

      var totalGpsBtsRecords = 0;
      var totalImuRecords = 0;

      for (final file in gpsBtsFiles) {
        totalGpsBtsRecords += await _countDataRows(file);
      }

      for (final file in imuFiles) {
        try {
          var content = await file.readAsString();
          if (content.startsWith('\uFEFF')) {
            content = content.substring(1);
          }
          final rows = const CsvToListConverter().convert(content);
          if (rows.length > 1) {
            totalImuRecords += rows.length - 1;
          }
        } catch (_) {}
      }

      return <String, dynamic>{
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
      return <String, dynamic>{};
    }
  }
}
