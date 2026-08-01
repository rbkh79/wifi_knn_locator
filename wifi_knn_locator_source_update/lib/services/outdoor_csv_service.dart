import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'outdoor_gps_bts_service.dart';
import 'outdoor_imu_service.dart';

/// CSV persistence and phone export for outdoor datasets.
class OutdoorCsvService {
  static const ListToCsvConverter _converter = ListToCsvConverter();

  static Future<String?> createGpsBtsWifiSessionFile({
    required String sessionId,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final safeSession = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File(
        '${directory.path}/outdoor_gps_bts_wifi_$safeSession.csv',
      );
      final header = _converter.convert(<List<dynamic>>[
        OutdoorGpsBtsRecord.csvHeader,
      ]);
      await file.writeAsString('$header\n', flush: true);
      return file.path;
    } catch (e, stackTrace) {
      debugPrint('Could not create outdoor CSV: $e\n$stackTrace');
      return null;
    }
  }

  /// Appends one row immediately. This protects long recordings against loss.
  static Future<void> appendGpsBtsWifiRecord(
    String filePath,
    OutdoorGpsBtsRecord record,
  ) async {
    final line = _converter.convert(<List<dynamic>>[record.toCsvRow()]);
    await File(filePath).writeAsString(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Backward-compatible batch writer.
  static Future<String?> saveGpsBtsRecords(
    List<OutdoorGpsBtsRecord> records,
  ) async {
    if (records.isEmpty) return null;
    final sessionId = records.first.sessionId;
    final path = await createGpsBtsWifiSessionFile(sessionId: sessionId);
    if (path == null) return null;
    for (final record in records) {
      await appendGpsBtsWifiRecord(path, record);
    }
    return path;
  }

  static Future<List<File>> getGpsBtsWifiCsvFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.csv') &&
                (file.path.contains('outdoor_gps_bts_wifi_') ||
                    file.path.contains('outdoor_gps_bts_')),
          )
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
      return files;
    } catch (e) {
      debugPrint('Error listing outdoor GPS+BTS+WiFi files: $e');
      return <File>[];
    }
  }

  /// Kept so existing callers continue to compile.
  static Future<List<File>> getGpsBtsCsvFiles() => getGpsBtsWifiCsvFiles();

  /// Opens the Android/iOS share sheet so the researcher can save to Files,
  /// Drive, email, messaging apps, or another phone folder.
  static Future<String?> exportAndShareGpsBtsWifiCsv() async {
    try {
      final files = await getGpsBtsWifiCsvFiles();
      if (files.isEmpty) {
        debugPrint('No outdoor GPS+BTS+WiFi CSV file exists');
        return null;
      }

      final source = files.first;
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final exportFile = File(
        '${directory.path}/outdoor_gps_bts_wifi_export_$stamp.csv',
      );
      await source.copy(exportFile.path);

      await Share.shareXFiles(
        <XFile>[XFile(exportFile.path)],
        subject: 'Outdoor GPS + BTS + Wi-Fi research dataset',
        text: 'Outdoor synchronized GPS+BTS+WiFi CSV dataset',
      );
      return exportFile.path;
    } catch (e, stackTrace) {
      debugPrint('Outdoor export error: $e\n$stackTrace');
      return null;
    }
  }

  /// Old UI method now routes to the corrected combined export.
  static Future<void> exportAndOpenGpsBtsCsv() async {
    await exportAndShareGpsBtsWifiCsv();
  }

  static Future<void> shareGpsBtsCsv() async {
    await exportAndShareGpsBtsWifiCsv();
  }

  static Future<void> openLatestGpsBtsWifiCsv() async {
    final files = await getGpsBtsWifiCsvFiles();
    if (files.isNotEmpty) {
      await OpenFile.open(files.first.path);
    }
  }

  // -------------------- Existing IMU support --------------------

  static Future<String?> saveImuRecords(
    List<OutdoorImuRecord> records,
  ) async {
    if (records.isEmpty) return null;
    try {
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/outdoor_imu_$timestamp.csv');
      final rows = <List<dynamic>>[
        OutdoorImuRecord.csvHeader,
        ...records.map((record) => record.toCsvRow()),
      ];
      await file.writeAsString(_converter.convert(rows), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('Error saving IMU CSV: $e');
      return null;
    }
  }

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
      debugPrint('Error listing IMU files: $e');
      return <File>[];
    }
  }

  static Future<void> exportAndOpenImuCsv() async {
    final files = await getImuCsvFiles();
    if (files.isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final exportFile = File('${directory.path}/outdoor_imu_export.csv');
    await files.first.copy(exportFile.path);
    await OpenFile.open(exportFile.path);
  }

  static Future<void> shareImuCsv() async {
    final files = await getImuCsvFiles();
    if (files.isEmpty) return;
    await Share.shareXFiles(
      <XFile>[XFile(files.first.path)],
      text: 'Outdoor IMU Dataset',
    );
  }

  static Future<void> clearAllOutdoorCsvFiles() async {
    final gpsBtsWifiFiles = await getGpsBtsWifiCsvFiles();
    final imuFiles = await getImuCsvFiles();
    final paths = <String>{
      ...gpsBtsWifiFiles.map((file) => file.path),
      ...imuFiles.map((file) => file.path),
    };
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  static Future<Map<String, dynamic>> getOutdoorCsvStatistics() async {
    final radioFiles = await getGpsBtsWifiCsvFiles();
    final imuFiles = await getImuCsvFiles();
    return <String, dynamic>{
      'gps_bts_wifi_files': radioFiles.length,
      'gps_bts_files': radioFiles.length, // legacy key
      'imu_files': imuFiles.length,
      'total_files': radioFiles.length + imuFiles.length,
    };
  }
}
