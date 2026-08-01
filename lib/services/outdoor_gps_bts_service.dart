import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../cell_scanner.dart';
import '../data_model.dart';
import '../utils/privacy_utils.dart';
import '../wifi_scanner.dart';
import 'outdoor_csv_service.dart';

/// Continuous outdoor research recorder.
///
/// Every CSV row is one synchronized sample containing GPS, the serving cell,
/// neighboring cells and all visible Wi-Fi access points. Rows are appended to
/// disk immediately so a long collection session is not lost if the app stops.
class OutdoorGpsBtsService {
  static OutdoorGpsBtsService? _instance;

  static OutdoorGpsBtsService get instance {
    _instance ??= OutdoorGpsBtsService._internal();
    return _instance!;
  }

  OutdoorGpsBtsService._internal();

  bool _isRecording = false;
  bool _captureInProgress = false;
  bool _includeBts = true;
  bool _includeWifi = true;
  Timer? _recordingTimer;

  final List<OutdoorGpsBtsRecord> _records = <OutdoorGpsBtsRecord>[];
  Duration _samplingInterval = const Duration(seconds: 5);

  Function(int recordCount)? _onRecordCountChanged;
  Function(String status)? _onStatusChanged;

  String? _sessionId;
  String? _activeCsvPath;
  String? _deviceId;

  bool get isRecording => _isRecording;
  int get recordCount => _records.length;
  String? get activeCsvPath => _activeCsvPath;
  String? get sessionId => _sessionId;
  List<OutdoorGpsBtsRecord> get records =>
      List<OutdoorGpsBtsRecord>.unmodifiable(_records);

  Future<bool> startRecording({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
    Duration samplingInterval = const Duration(seconds: 5),
    bool includeBts = true,
    bool includeWifi = true,
  }) async {
    if (_isRecording) {
      _notifyStatus('Outdoor recording is already active');
      return false;
    }

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;
    _samplingInterval = samplingInterval;
    _includeBts = includeBts;
    _includeWifi = includeWifi;

    try {
      if (!await _ensureGpsPermission()) return false;

      if (_includeBts) {
        final hasPermission = await CellScanner.checkPermissions();
        if (!hasPermission && !await CellScanner.requestPermissions()) {
          _notifyStatus('BTS permission denied');
          return false;
        }
      }

      if (_includeWifi) {
        final hasPermission = await WifiScanner.checkPermissions();
        if (!hasPermission && !await WifiScanner.requestPermissions()) {
          // Do not lose the complete session just because Wi-Fi was denied.
          _includeWifi = false;
          _notifyStatus('Wi-Fi permission denied; recording GPS+BTS only');
        }
      }

      _records.clear();
      _onRecordCountChanged?.call(0);
      _deviceId = await PrivacyUtils.getDeviceId();
      _sessionId = 'outdoor_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      _activeCsvPath = await OutdoorCsvService.createGpsBtsWifiSessionFile(
        sessionId: _sessionId!,
      );

      if (_activeCsvPath == null) {
        _notifyStatus('Could not create outdoor CSV file');
        return false;
      }

      _isRecording = true;
      _notifyStatus('Recording GPS+BTS+WiFi...');

      await _captureSample();
      _recordingTimer = Timer.periodic(_samplingInterval, (_) {
        _captureSample();
      });
      return true;
    } catch (e, stackTrace) {
      debugPrint('Outdoor recorder start error: $e\n$stackTrace');
      _isRecording = false;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _notifyStatus('Outdoor recording error: $e');
      return false;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    for (var i = 0; i < 40 && _captureInProgress; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final path = _activeCsvPath;
    _notifyStatus(
      path == null
          ? 'Recording stopped: ${_records.length} records'
          : 'Saved ${_records.length} records: $path',
    );
  }

  Future<void> _captureSample() async {
    if (!_isRecording || _captureInProgress) return;
    _captureInProgress = true;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 12),
      );

      final Future<CellScanResult?> cellFuture = _includeBts
          ? CellScanner.performScan()
              .timeout(const Duration(seconds: 10))
              .then<CellScanResult?>((value) => value)
              .catchError((Object e) {
              debugPrint('Outdoor BTS scan error: $e');
              return null;
            })
          : Future<CellScanResult?>.value(null);

      final Future<WifiScanResult?> wifiFuture = _includeWifi
          ? WifiScanner.performScan()
              .timeout(const Duration(seconds: 12))
              .then<WifiScanResult?>((value) => value)
              .catchError((Object e) {
              debugPrint('Outdoor Wi-Fi scan error: $e');
              return null;
            })
          : Future<WifiScanResult?>.value(null);

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        cellFuture,
        wifiFuture,
      ]);
      final cellResult = results[0] as CellScanResult?;
      final wifiResult = results[1] as WifiScanResult?;

      CellTowerInfo? servingCell = cellResult?.servingCell;
      final neighbors = List<CellTowerInfo>.from(
        cellResult?.neighboringCells ?? const <CellTowerInfo>[],
      );

      var servingCellWasFallback = false;
      if (servingCell == null && neighbors.isNotEmpty) {
        servingCell = neighbors.removeAt(0);
        servingCellWasFallback = true;
      }

      final sampleIndex = _records.length + 1;
      final sampleId = '${_sessionId!}_${sampleIndex.toString().padLeft(6, '0')}';
      final record = OutdoorGpsBtsRecord(
        sampleId: sampleId,
        sessionId: _sessionId!,
        deviceId: _deviceId ?? '',
        timestamp: DateTime.now().toUtc(),
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        bearing: position.heading,
        provider: 'GPS',
        servingCell: servingCell,
        servingCellWasFallback: servingCellWasFallback,
        neighboringCells: neighbors,
        wifiReadings: List<WifiReading>.from(
          wifiResult?.accessPoints ?? const <WifiReading>[],
        ),
        cellScanSucceeded: cellResult != null,
        wifiScanSucceeded: wifiResult != null,
      );

      final path = _activeCsvPath;
      if (path == null) {
        throw StateError('Outdoor CSV path is not initialized');
      }

      await OutdoorCsvService.appendGpsBtsWifiRecord(path, record);
      _records.add(record);
      _onRecordCountChanged?.call(_records.length);

      _notifyStatus(
        'GPS ±${position.accuracy.toStringAsFixed(0)} m | '
        'Cell ${servingCell?.cellId ?? '-'} | '
        '${neighbors.length} neighbors | '
        '${record.wifiReadings.length} Wi-Fi APs',
      );
    } catch (e, stackTrace) {
      debugPrint('Outdoor sample error: $e\n$stackTrace');
      _notifyStatus('Sample skipped: $e');
    } finally {
      _captureInProgress = false;
    }
  }

  Future<bool> _ensureGpsPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _notifyStatus('GPS service is disabled');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _notifyStatus('GPS permission denied');
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      _notifyStatus('GPS permission permanently denied. Enable it in Settings.');
      return false;
    }
    return true;
  }

  void _notifyStatus(String status) {
    _onStatusChanged?.call(status);
    debugPrint('[OutdoorRecorder] $status');
  }

  void clearRecords() {
    if (_isRecording) return;
    _records.clear();
    _onRecordCountChanged?.call(0);
  }

  Future<bool> startGpsOnlyTest({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
  }) {
    return startRecording(
      onRecordCountChanged: onRecordCountChanged,
      onStatusChanged: onStatusChanged,
      includeBts: false,
      includeWifi: false,
      samplingInterval: const Duration(seconds: 5),
    );
  }
}

class OutdoorGpsBtsRecord {
  final String sampleId;
  final String sessionId;
  final String deviceId;
  final DateTime timestamp;

  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final String provider;

  final CellTowerInfo? servingCell;
  final bool servingCellWasFallback;
  final List<CellTowerInfo> neighboringCells;
  final List<WifiReading> wifiReadings;
  final bool cellScanSucceeded;
  final bool wifiScanSucceeded;

  OutdoorGpsBtsRecord({
    required this.sampleId,
    required this.sessionId,
    required this.deviceId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.bearing,
    required this.provider,
    this.servingCell,
    this.servingCellWasFallback = false,
    this.neighboringCells = const <CellTowerInfo>[],
    this.wifiReadings = const <WifiReading>[],
    this.cellScanSucceeded = false,
    this.wifiScanSucceeded = false,
  });

  int? get eNodeBId {
    final cellId = servingCell?.cellId;
    if (cellId == null || cellId < 0) return null;
    if ((servingCell?.networkType ?? '').toUpperCase() != 'LTE') return null;
    return cellId ~/ 256;
  }

  int? get localCellId {
    final cellId = servingCell?.cellId;
    if (cellId == null || cellId < 0) return null;
    if ((servingCell?.networkType ?? '').toUpperCase() != 'LTE') return null;
    return cellId % 256;
  }

  WifiReading? get strongestWifi {
    if (wifiReadings.isEmpty) return null;
    return wifiReadings.reduce((a, b) => a.rssi >= b.rssi ? a : b);
  }

  String get gpsQuality {
    final value = accuracy;
    if (value == null) return 'unknown';
    if (value <= 10) return 'excellent';
    if (value <= 20) return 'good';
    if (value <= 30) return 'acceptable';
    if (value <= 50) return 'poor';
    return 'very_poor';
  }

  List<dynamic> toCsvRow() {
    final cell = servingCell;
    final strongest = strongestWifi;
    return <dynamic>[
      sampleId,
      sessionId,
      deviceId,
      timestamp.toIso8601String(),
      latitude,
      longitude,
      altitude ?? '',
      accuracy ?? '',
      gpsQuality,
      speed ?? '',
      bearing ?? '',
      provider,
      cellScanSucceeded,
      servingCellWasFallback,
      cell?.mcc ?? '',
      cell?.mnc ?? '',
      cell?.lac ?? '',
      cell?.tac ?? '',
      cell?.cellId ?? '',
      eNodeBId ?? '',
      localCellId ?? '',
      cell?.networkType ?? '',
      cell?.signalStrength ?? '',
      cell?.psc ?? '',
      cell?.pci ?? '',
      cell?.earfcn ?? '',
      neighboringCells.length,
      jsonEncode(neighboringCells.map(_cellToJson).toList()),
      wifiScanSucceeded,
      wifiReadings.length,
      strongest?.bssid ?? '',
      strongest?.rssi ?? '',
      strongest?.frequency ?? '',
      jsonEncode(wifiReadings.map(_wifiToJson).toList()),
    ];
  }

  static Map<String, dynamic> _cellToJson(CellTowerInfo cell) {
    return <String, dynamic>{
      'cell_id': cell.cellId,
      'lac': cell.lac,
      'tac': cell.tac,
      'mcc': cell.mcc,
      'mnc': cell.mnc,
      'signal_strength': cell.signalStrength,
      'network_type': cell.networkType,
      'psc': cell.psc,
      'pci': cell.pci,
      'earfcn': cell.earfcn,
    };
  }

  static int? _wifiChannel(int? frequencyMhz) {
    if (frequencyMhz == null) return null;
    if (frequencyMhz == 2484) return 14;
    if (frequencyMhz >= 2412 && frequencyMhz <= 2472) {
      return ((frequencyMhz - 2407) / 5).round();
    }
    if (frequencyMhz >= 5000 && frequencyMhz <= 5900) {
      return ((frequencyMhz - 5000) / 5).round();
    }
    if (frequencyMhz >= 5955 && frequencyMhz <= 7115) {
      return ((frequencyMhz - 5950) / 5).round();
    }
    return null;
  }

  static Map<String, dynamic> _wifiToJson(WifiReading wifi) {
    return <String, dynamic>{
      'bssid': wifi.bssid,
      'rssi': wifi.rssi,
      'frequency': wifi.frequency,
      'channel': _wifiChannel(wifi.frequency),
    };
  }

  static const List<String> csvHeader = <String>[
    'SampleID',
    'SessionID',
    'DeviceID',
    'TimestampUTC',
    'Latitude',
    'Longitude',
    'AltitudeM',
    'GpsAccuracyM',
    'GpsQuality',
    'SpeedMps',
    'BearingDeg',
    'Provider',
    'CellScanSucceeded',
    'ServingCellWasFallback',
    'MCC',
    'MNC',
    'LAC',
    'TAC',
    'CellID',
    'ENodeBID',
    'LocalCellID',
    'NetworkType',
    'SignalStrengthDbm',
    'PSC',
    'PCI',
    'EARFCN',
    'NeighborCellCount',
    'NeighborCellsJSON',
    'WifiScanSucceeded',
    'WifiAPCount',
    'StrongestWifiBSSID',
    'StrongestWifiRSSI',
    'StrongestWifiFrequencyMHz',
    'WifiReadingsJSON',
  ];
}
