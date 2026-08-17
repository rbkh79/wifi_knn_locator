import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'outdoor_gps_bts_service.dart';
import 'outdoor_imu_service.dart';


class OutdoorXlsxExportResult {
  final String xlsxPath;
  final String? downloadsLocation;

  const OutdoorXlsxExportResult({
    required this.xlsxPath,
    this.downloadsLocation,
  });

  bool get savedToDownloads =>
      downloadsLocation != null && downloadsLocation!.isNotEmpty;
}

/// Durable storage/export service for Outdoor datasets.
///
/// GPS+BTS reliability rules:
/// - create the session CSV before recording starts;
/// - append every accepted sample immediately with flush=true;
/// - final consistency rewrite on Stop;
/// - interrupted sessions remain discoverable after app restart;
/// - Researcher Mode export creates a real XLSX and opens it with a
///   spreadsheet application. The export button does NOT call the share sheet.
class OutdoorCsvService {
  static const ListToCsvConverter _csvWriter = ListToCsvConverter();
  static const String _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const MethodChannel _fileExportChannel =
      MethodChannel('wifi_knn_locator/file_export');

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

  /// Create the durable GPS+BTS session file before the first sample.
  ///
  /// A UTF-8 BOM is written so the emergency CSV can also be opened cleanly
  /// by Excel if needed.
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

  /// Append exactly one record and force it to storage immediately.
  ///
  /// This is the important crash-resilience path: completed samples do not
  /// wait in RAM until Stop Recording.
  static Future<bool> appendGpsBtsRecord(
    String filePath,
    OutdoorGpsBtsRecord record,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[OutdoorCSV] Append target missing: $filePath');
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

  /// Final consistency save using temp + backup.
  ///
  /// The existing valid session is kept recoverable if the final rewrite fails.
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

  /// Backward-compatible full save API.
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

  /// Existing IMU save behavior is retained.
  static Future<String?> saveImuRecords(
    List<OutdoorImuRecord> records,
  ) async {
    if (records.isEmpty) {
      debugPrint('No IMU records to save');
      return null;
    }

    try {
      final fileName = 'outdoor_imu_${_safeTimestamp()}.csv';
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

  /// All recoverable GPS+BTS session files, newest first.
  ///
  /// A session interrupted by app close/crash is intentionally included.
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

    // A process kill can theoretically interrupt the final append halfway
    // through a CSV row. Every completed append ends with a newline, so drop
    // only an unterminated tail and keep all previously completed samples.
    if (!content.endsWith('\n')) {
      final lastCompleteNewline = content.lastIndexOf('\n');
      if (lastCompleteNewline >= 0) {
        content = content.substring(0, lastCompleteNewline + 1);
      }
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
        if (rows.length > 1) return file;
      } catch (_) {}
    }
    return null;
  }

  static const Set<String> _identifierColumns = <String>{
    'Timestamp',
    'MCC',
    'MNC',
    'LAC',
    'TAC',
    'CellID',
    'ENodeBID',
    'LocalCellID',
    'PSC',
    'PCI',
    'EARFCN',
    'Band',
    'NeighborCellsJSON',
  };

  static CellValue _excelValue(String header, dynamic value) {
    if (value == null || value == '') {
      return TextCellValue('');
    }

    // Keep identifiers exact and prevent spreadsheet scientific notation.
    if (_identifierColumns.contains(header)) {
      return TextCellValue(value.toString());
    }

    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value.toString());
  }

  /// Create a genuine XLSX workbook from a durable GPS+BTS session.
  ///
  /// If [csvPath] is supplied, that exact session is exported. Otherwise the
  /// newest non-empty recoverable session is used, including a session from a
  /// previous interrupted app run.
  static Future<String?> exportGpsBtsXlsx({
    String? csvPath,
  }) async {
    try {
      File? source;

      if (csvPath != null) {
        final candidate = File(csvPath);
        if (await candidate.exists()) {
          final rows = await _readCsvRows(candidate);
          if (rows.length > 1) source = candidate;
        }
      }

      source ??= await _latestGpsBtsDataFile();
      if (source == null) {
        debugPrint('[OutdoorCSV] No non-empty GPS+BTS session to export');
        return null;
      }

      final rows = await _readCsvRows(source);
      if (rows.length <= 1) return null;

      final headers = rows.first.map((v) => v.toString()).toList();
      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();
      const sheetName = 'Outdoor_GPS_BTS';

      if (defaultSheet != null && defaultSheet != sheetName) {
        workbook.rename(defaultSheet, sheetName);
      }

      final sheet = workbook[sheetName];

      // Header row.
      sheet.appendRow(
        headers.map<CellValue>((h) => TextCellValue(h)).toList(),
      );

      // Data rows.
      for (final row in rows.skip(1)) {
        final values = <CellValue>[];
        for (var i = 0; i < headers.length; i++) {
          final value = i < row.length ? row[i] : '';
          values.add(_excelValue(headers[i], value));
        }
        sheet.appendRow(values);
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

      if (!await xlsxFile.exists() || await xlsxFile.length() == 0) {
        debugPrint('[OutdoorCSV] XLSX verification failed');
        return null;
      }

      debugPrint('[OutdoorCSV] XLSX created: ${xlsxFile.path}');
      return xlsxFile.path;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] XLSX export failed: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }


  /// Copy the generated XLSX to the public Android Downloads collection.
  ///
  /// The native side uses MediaStore on Android 10+ so no share sheet is
  /// required. Failure here does not destroy the internal XLSX; it is still
  /// opened with the spreadsheet app.
  static Future<String?> _copyXlsxToPublicDownloads(String xlsxPath) async {
    if (!Platform.isAndroid) return null;

    try {
      final file = File(xlsxPath);
      if (!await file.exists()) return null;

      final displayName = _fileName(file);
      final uri = await _fileExportChannel.invokeMethod<String>(
        'saveFileToDownloads',
        <String, dynamic>{
          'sourcePath': xlsxPath,
          'displayName': displayName,
          'mimeType': _xlsxMime,
        },
      );

      debugPrint('[OutdoorCSV] Public Downloads copy: $uri');
      return uri;
    } on MissingPluginException catch (e) {
      debugPrint('[OutdoorCSV] Downloads channel unavailable: $e');
      return null;
    } on PlatformException catch (e) {
      debugPrint('[OutdoorCSV] Downloads copy failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[OutdoorCSV] Downloads copy failed: $e');
      return null;
    }
  }

  /// Researcher Mode button target.
  ///
  /// Creates a real XLSX and opens it
  /// using Android's file-open Intent. It never calls Share.shareXFiles.
  ///
  /// Returns the generated XLSX path when creation succeeded. If Excel/WPS/
  /// Sheets is not installed, the file still exists and the OpenFile result is
  /// logged, but no fake "share" success is shown.
  static Future<OutdoorXlsxExportResult?> exportAndOpenGpsBtsXlsx({
    String? csvPath,
  }) async {
    try {
      final xlsxPath = await exportGpsBtsXlsx(csvPath: csvPath);
      if (xlsxPath == null) return null;

      // Keep a user-visible copy in Downloads without using Share Sheet.
      final downloadsLocation = await _copyXlsxToPublicDownloads(xlsxPath);

      await OpenFile.open(
        xlsxPath,
        type: _xlsxMime,
      );

      debugPrint('[OutdoorCSV] XLSX open requested: $xlsxPath');
      return OutdoorXlsxExportResult(
        xlsxPath: xlsxPath,
        downloadsLocation: downloadsLocation,
      );
    } catch (e, stackTrace) {
      debugPrint('[OutdoorCSV] Error opening GPS+BTS XLSX: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// Legacy API kept so existing callers elsewhere in the project continue
  /// to compile. Researcher Mode should call [exportAndOpenGpsBtsXlsx] when it
  /// needs the result path.
  static Future<void> exportAndOpenGpsBtsCsv() async {
    await exportAndOpenGpsBtsXlsx();
  }

  /// IMU export also opens a real XLSX instead of the share sheet.
  static Future<void> exportAndOpenImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) {
        debugPrint('No IMU CSV files to export');
        return;
      }

      var content = await files.first.readAsString();
      if (content.startsWith('\uFEFF')) content = content.substring(1);
      final rows = const CsvToListConverter(
        shouldParseNumbers: true,
      ).convert(content);
      if (rows.length <= 1) return;

      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();
      const sheetName = 'Outdoor_IMU_GPS';
      if (defaultSheet != null && defaultSheet != sheetName) {
        workbook.rename(defaultSheet, sheetName);
      }
      final sheet = workbook[sheetName];

      for (final row in rows) {
        sheet.appendRow(
          row
              .map<CellValue>((value) => TextCellValue(value?.toString() ?? ''))
              .toList(),
        );
      }

      final bytes = workbook.save();
      if (bytes == null || bytes.isEmpty) return;

      final directory = await _documentsDirectory();
      final xlsxFile = File(
        '${directory.path}/outdoor_imu_export_${_safeTimestamp()}.xlsx',
      );
      await xlsxFile.writeAsBytes(bytes, flush: true);

      await OpenFile.open(xlsxFile.path, type: _xlsxMime);
      return;
    } catch (e, stackTrace) {
      debugPrint('Error exporting/opening IMU XLSX: $e');
      debugPrint('$stackTrace');
      return;
    }
  }

  /// Optional manual sharing utility. Researcher Mode export does not call it.
  /// Signature is kept compatible with the original service.
  static Future<void> shareGpsBtsCsv() async {
    try {
      final file = await _latestGpsBtsDataFile();
      if (file == null) return;

      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: 'Outdoor GPS+BTS Dataset (CSV)',
      );
    } catch (e) {
      debugPrint('Error sharing GPS+BTS CSV: $e');
    }
  }

  /// Optional manual sharing utility. Researcher Mode export does not call it.
  static Future<void> shareImuCsv() async {
    try {
      final files = await getImuCsvFiles();
      if (files.isEmpty) return;
      await Share.shareXFiles(
        <XFile>[XFile(files.first.path)],
        text: 'Outdoor IMU Dataset',
      );
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
          if (content.startsWith('\uFEFF')) content = content.substring(1);
          final rows = const CsvToListConverter().convert(content);
          if (rows.length > 1) totalImuRecords += rows.length - 1;
        } catch (_) {}
      }

      return <String, dynamic>{
        'gps_bts_file_count': gpsBtsFiles.length,
        'imu_file_count': imuFiles.length,
        'total_gps_bts_records': totalGpsBtsRecords,
        'total_imu_records': totalImuRecords,
        'latest_gps_bts_file':
            gpsBtsFiles.isNotEmpty ? gpsBtsFiles.first.path : null,
        'latest_imu_file': imuFiles.isNotEmpty ? imuFiles.first.path : null,
      };
    } catch (e) {
      debugPrint('Error getting outdoor statistics: $e');
      return <String, dynamic>{};
    }
  }
}
