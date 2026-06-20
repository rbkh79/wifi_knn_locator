import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';

/// CSV Manager برای ذخیره Ground Truth و Fingerprint Dataset
class IndoorCsvManager {
  static File? _osmPointsFile;
  static File? _fingerprintsFile;
  static bool _osmHeaderWritten = false;
  static bool _fingerprintHeaderWritten = false;
  
  /// Initialize CSV files
  static Future<void> initialize() async {
    final directory = await getApplicationDocumentsDirectory();
    
    // osm_points.csv
    final osmPointsPath = '${directory.path}/osm_points.csv';
    _osmPointsFile = File(osmPointsPath);
    if (await _osmPointsFile!.exists()) {
      final content = await _osmPointsFile!.readAsString();
      _osmHeaderWritten = content.isNotEmpty && content.contains('Timestamp');
    } else {
      await _writeOsmHeader();
      _osmHeaderWritten = true;
    }
    
    // fingerprints.csv
    final fingerprintsPath = '${directory.path}/fingerprints.csv';
    _fingerprintsFile = File(fingerprintsPath);
    if (await _fingerprintsFile!.exists()) {
      final content = await _fingerprintsFile!.readAsString();
      _fingerprintHeaderWritten = content.isNotEmpty && content.contains('SampleID');
    } else {
      await _writeFingerprintHeader();
      _fingerprintHeaderWritten = true;
    }
    
    debugPrint('IndoorCsvManager initialized: OSM=$osmPointsPath, Fingerprints=$fingerprintsPath');
  }
  
  /// نوشتن header در فایل osm_points.csv
  static Future<void> _writeOsmHeader() async {
    if (_osmPointsFile == null) return;
    
    final header = [
      'Timestamp',
      'Latitude',
      'Longitude',
      'Building',
      'Floor',
      'Room',
      'ReferencePointID',
      'Source',
    ];
    
    final csvString = const ListToCsvConverter().convert([header]);
    await _osmPointsFile!.writeAsString(csvString, mode: FileMode.write);
    debugPrint('OSM Points CSV header written');
  }
  
  /// نوشتن header در فایل fingerprints.csv
  static Future<void> _writeFingerprintHeader() async {
    if (_fingerprintsFile == null) return;
    
    final header = [
      'SampleID',
      'ReferencePointID',
      'Timestamp',
      'Latitude',
      'Longitude',
      'Building',
      'Floor',
      'Room',
      'CellID',
      'TAC',
      'PCI',
      'CellSignal',
      'NetworkType',
      'WifiBSSID',
      'WifiSSID',
      'WifiRSSI',
      'WifiFrequency',
      'GPS_Latitude',
      'GPS_Longitude',
      'GPS_Accuracy',
      'Source',
    ];
    
    final csvString = const ListToCsvConverter().convert([header]);
    await _fingerprintsFile!.writeAsString(csvString, mode: FileMode.write);
    debugPrint('Fingerprints CSV header written');
  }
  
  /// ذخیره یک Ground Truth Point
  static Future<void> saveOsmPoint(Map<String, dynamic> point) async {
    if (_osmPointsFile == null) await initialize();
    
    final row = [
      point['Timestamp'],
      point['Latitude'],
      point['Longitude'],
      point['Building'],
      point['Floor'],
      point['Room'],
      point['ReferencePointID'],
      point['Source'],
    ];
    
    final csvString = const ListToCsvConverter().convert([row]);
    await _osmPointsFile!.writeAsString('\n$csvString', mode: FileMode.append);
    debugPrint('✓ OSM Point saved: ${point['ReferencePointID']}');
  }
  
  /// ذخیره یک Fingerprint
  static Future<void> saveFingerprint(Map<String, dynamic> fingerprint) async {
    if (_fingerprintsFile == null) await initialize();
    
    final row = [
      fingerprint['SampleID'],
      fingerprint['ReferencePointID'],
      fingerprint['Timestamp'],
      fingerprint['Latitude'],
      fingerprint['Longitude'],
      fingerprint['Building'],
      fingerprint['Floor'],
      fingerprint['Room'],
      fingerprint['CellID'],
      fingerprint['TAC'],
      fingerprint['PCI'],
      fingerprint['CellSignal'],
      fingerprint['NetworkType'],
      fingerprint['WifiBSSID'],
      fingerprint['WifiSSID'],
      fingerprint['WifiRSSI'],
      fingerprint['WifiFrequency'],
      fingerprint['GPS_Latitude'],
      fingerprint['GPS_Longitude'],
      fingerprint['GPS_Accuracy'],
      fingerprint['Source'],
    ];
    
    final csvString = const ListToCsvConverter().convert([row]);
    await _fingerprintsFile!.writeAsString('\n$csvString', mode: FileMode.append);
    debugPrint('✓ Fingerprint saved: ${fingerprint['SampleID']}');
  }
  
  /// دریافت SampleID بعدی برای یک Reference Point
  static Future<String> getNextSampleId(String referencePointId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'sample_id_$referencePointId';
    int currentSampleId = prefs.getInt(key) ?? 0;
    currentSampleId++;
    await prefs.setInt(key, currentSampleId);
    return '${referencePointId}_S${currentSampleId.toString().padLeft(3, '0')}';
  }
  
  /// بارگذاری نقاط ذخیره‌شده
  static Future<List<Map<String, dynamic>>> loadOsmPoints() async {
    if (_osmPointsFile == null) await initialize();
    
    try {
      final content = await _osmPointsFile!.readAsString();
      final rows = const CsvToListConverter().convert(content);
      
      if (rows.isEmpty) return [];
      
      // Skip header
      final dataRows = rows.skip(1);
      
      final points = dataRows.map((row) {
        return {
          'Timestamp': row[0],
          'Latitude': row[1],
          'Longitude': row[2],
          'Building': row[3],
          'Floor': row[4],
          'Room': row[5],
          'ReferencePointID': row[6],
          'Source': row[7],
        };
      }).toList();
      
      return points;
    } catch (e) {
      debugPrint('Error loading OSM points: $e');
      return [];
    }
  }
  
  /// بارگذاری آمار
  static Future<Map<String, int>> loadStatistics() async {
    if (_fingerprintsFile == null) await initialize();
    
    try {
      final content = await _fingerprintsFile!.readAsString();
      final rows = const CsvToListConverter().convert(content);
      
      if (rows.isEmpty) return {'totalReferencePoints': 0, 'totalSamples': 0, 'samplesPerReferencePoint': {}};
      
      // Skip header
      final dataRows = rows.skip(1);
      
      final referencePoints = <String>{};
      final samplesPerReferencePoint = <String, int>{};
      
      for (final row in dataRows) {
        final referencePointId = row[1].toString();
        referencePoints.add(referencePointId);
        samplesPerReferencePoint[referencePointId] = (samplesPerReferencePoint[referencePointId] ?? 0) + 1;
      }
      
      return {
        'totalReferencePoints': referencePoints.length,
        'totalSamples': dataRows.length,
        'samplesPerReferencePoint': samplesPerReferencePoint,
      };
    } catch (e) {
      debugPrint('Error loading statistics: $e');
      return {'totalReferencePoints': 0, 'totalSamples': 0, 'samplesPerReferencePoint': {}};
    }
  }
  
  /// پاک کردن فایل‌های CSV
  static Future<void> clearCsv() async {
    if (_osmPointsFile != null && await _osmPointsFile!.exists()) {
      await _osmPointsFile!.delete();
    }
    if (_fingerprintsFile != null && await _fingerprintsFile!.exists()) {
      await _fingerprintsFile!.delete();
    }
    _osmHeaderWritten = false;
    _fingerprintHeaderWritten = false;
    await initialize();
  }
  
  /// ذخیره فایل OSM Points در Downloads
  static Future<String?> saveOsmPointsToDownloads({String fileName = 'osm_points.csv'}) async {
    if (_osmPointsFile == null) await initialize();
    if (_osmPointsFile == null) return null;
    final csvContent = await _osmPointsFile!.readAsString();
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final outFile = File('${directory.path}/$fileName');
      await outFile.writeAsString(csvContent, flush: true);
      debugPrint('OSM Points CSV saved to app documents: ${outFile.path}');
      return outFile.path;
    } catch (e) {
      debugPrint('Error saving OSM Points CSV: $e');
      return null;
    }
  }
  
  /// ذخیره فایل Fingerprints در Downloads
  static Future<String?> saveFingerprintsToDownloads({String fileName = 'fingerprints.csv'}) async {
    if (_fingerprintsFile == null) await initialize();
    if (_fingerprintsFile == null) return null;
    final csvContent = await _fingerprintsFile!.readAsString();
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final outFile = File('${directory.path}/$fileName');
      await outFile.writeAsString(csvContent, flush: true);
      debugPrint('Fingerprints CSV saved to app documents: ${outFile.path}');
      return outFile.path;
    } catch (e) {
      debugPrint('Error saving Fingerprints CSV: $e');
      return null;
    }
  }
}
