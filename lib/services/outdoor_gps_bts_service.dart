import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../cell_scanner.dart';
import '../data_model.dart';
import 'outdoor_csv_service.dart';

/// Continuous GPS + BTS recorder for outdoor research.
///
/// The existing recording/export workflow is preserved. This version only
/// enriches each row with LTE radio metrics that are useful for BTS-site and
/// distance estimation. Unsupported values remain empty in the CSV.
class OutdoorGpsBtsService {
  static OutdoorGpsBtsService? _instance;

  static OutdoorGpsBtsService get instance {
    _instance ??= OutdoorGpsBtsService._internal();
    return _instance!;
  }

  OutdoorGpsBtsService._internal();

  bool _isRecording = false;
  bool _captureInProgress = false;
  Timer? _recordingTimer;
  StreamSubscription<Position>? _positionStreamSubscription;

  final List<OutdoorGpsBtsRecord> _records = <OutdoorGpsBtsRecord>[];

  Function(int recordCount)? _onRecordCountChanged;
  Function(String status)? _onStatusChanged;
  Function(OutdoorGpsBtsRecord record)? _onLatestRecordChanged;

  bool get isRecording => _isRecording;
  int get recordCount => _records.length;
  OutdoorGpsBtsRecord? get latestRecord =>
      _records.isEmpty ? null : _records.last;

  Future<bool> startRecording({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
    Function(OutdoorGpsBtsRecord record)? onLatestRecordChanged,
  }) async {
    debugPrint('[OutdoorBTS] Start recording requested');
    if (_isRecording) {
      _notifyStatus('Outdoor GPS+BTS recording is already active');
      return false;
    }

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;
    _onLatestRecordChanged = onLatestRecordChanged;

    try {
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
        _notifyStatus('GPS permission permanently denied');
        return false;
      }

      final hasBtsPermission = await CellScanner.checkPermissions();
      if (!hasBtsPermission && !await CellScanner.requestPermissions()) {
        _notifyStatus('BTS permission denied');
        return false;
      }

      _records.clear();
      _onRecordCountChanged?.call(0);
      _isRecording = true;
      _notifyStatus('Recording GPS+BTS extended metrics...');

      // Capture the first sample immediately, then continue every second.
      await _captureCurrentSample();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _captureCurrentSample();
      });

      return true;
    } catch (e, stackTrace) {
      debugPrint('[OutdoorBTS] Start error: $e\n$stackTrace');
      _isRecording = false;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _notifyStatus('Error starting GPS+BTS recording: $e');
      return false;
    }
  }

  Future<void> stopRecording() async {
    debugPrint('[OutdoorBTS] Stop recording requested');
    if (!_isRecording) return;

    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    // Allow an in-flight sample to finish before generating the CSV.
    for (var i = 0; i < 50 && _captureInProgress; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (_records.isEmpty) {
      _notifyStatus('No records to save');
      return;
    }

    final filePath = await OutdoorCsvService.saveGpsBtsRecords(_records);
    if (filePath == null) {
      _notifyStatus('Could not save outdoor GPS+BTS CSV');
      return;
    }

    _notifyStatus('Saved ${_records.length} extended BTS records to CSV');
    debugPrint('[OutdoorBTS] CSV saved to $filePath');
  }

  Future<void> _captureCurrentSample() async {
    if (!_isRecording || _captureInProgress) return;
    _captureInProgress = true;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      await _onPositionUpdate(position);
    } catch (e, stackTrace) {
      debugPrint('[OutdoorBTS] Sample error: $e\n$stackTrace');
      _notifyStatus('Sample skipped: $e');
    } finally {
      _captureInProgress = false;
    }
  }

  Future<void> _onPositionUpdate(Position position) async {
    if (!_isRecording) return;

    CellScanResult? cellScanResult;
    try {
      cellScanResult = await CellScanner.performScan()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[OutdoorBTS] BTS scan error: $e');
    }

    CellTowerInfo? servingCell = cellScanResult?.servingCell;
    final neighboringCells = List<CellTowerInfo>.from(
      cellScanResult?.neighboringCells ?? const <CellTowerInfo>[],
    );

    var servingCellWasFallback = false;
    if (servingCell == null && neighboringCells.isNotEmpty) {
      servingCell = neighboringCells.first;
      servingCellWasFallback = true;
    }

    final record = OutdoorGpsBtsRecord(
      timestamp: DateTime.now().toUtc(),
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      bearing: position.heading,
      provider: 'GPS',
      mcc: servingCell?.mcc,
      mnc: servingCell?.mnc,
      lac: servingCell?.lac,
      tac: servingCell?.tac,
      cellId: servingCell?.cellId,
      signalStrength: servingCell?.signalStrength,
      networkType: servingCell?.networkType,
      psc: servingCell?.psc,
      pci: servingCell?.pci,
      earfcn: servingCell?.earfcn,
      rsrp: servingCell?.rsrp,
      rsrq: servingCell?.rsrq,
      sinr: servingCell?.sinr,
      cqi: servingCell?.cqi,
      timingAdvance: servingCell?.timingAdvance,
      asuLevel: servingCell?.asuLevel,
      signalLevel: servingCell?.level,
      bandwidth: servingCell?.bandwidth,
      band: servingCell?.band,
      registered: servingCell?.registered,
      servingCellWasFallback: servingCellWasFallback,
      neighboringCells: neighboringCells,
    );

    _records.add(record);
    _onRecordCountChanged?.call(_records.length);
    _onLatestRecordChanged?.call(record);

    _notifyStatus(
      'GPS ±${position.accuracy.toStringAsFixed(0)} m | '
      'Cell ${record.cellId ?? '-'} | '
      'PCI ${record.pci ?? '-'} | '
      'RSRP ${record.rsrp ?? record.signalStrength ?? '-'} dBm | '
      '${record.neighboringCells.length} neighbors',
    );
  }

  void _notifyStatus(String status) {
    _onStatusChanged?.call(status);
    debugPrint('[OutdoorBTS] $status');
  }

  void clearRecords() {
    if (_isRecording) return;
    _records.clear();
    _onRecordCountChanged?.call(0);
  }

  /// Kept for compatibility with the existing debug path.
  Future<bool> startGpsOnlyTest({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
  }) async {
    if (_isRecording) return false;

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;
    _onLatestRecordChanged = null;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notifyStatus('GPS service is disabled');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _notifyStatus('GPS permission denied');
        return false;
      }

      _records.clear();
      _isRecording = true;
      _notifyStatus('GPS-only test started');

      _recordingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!_isRecording || _captureInProgress) return;
        _captureInProgress = true;
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
          final record = OutdoorGpsBtsRecord(
            timestamp: DateTime.now().toUtc(),
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude,
            accuracy: position.accuracy,
            speed: position.speed,
            bearing: position.heading,
            provider: 'GPS',
          );
          _records.add(record);
          _onRecordCountChanged?.call(_records.length);
        } catch (e) {
          _notifyStatus('GPS-only sample skipped: $e');
        } finally {
          _captureInProgress = false;
        }
      });
      return true;
    } catch (e) {
      _isRecording = false;
      _notifyStatus('GPS-only test error: $e');
      return false;
    }
  }
}

/// One GPS + BTS research record.
///
/// Old columns remain in their original order. New research columns are
/// appended, so existing analysis scripts can still read the old fields.
class OutdoorGpsBtsRecord {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final String provider;

  final int? mcc;
  final int? mnc;
  final int? lac;
  final int? tac;
  final int? cellId;
  final int? signalStrength;
  final String? networkType;

  final int? psc;
  final int? pci;
  final int? earfcn;
  final int? rsrp;
  final int? rsrq;
  final int? sinr;
  final int? cqi;
  final int? timingAdvance;
  final int? asuLevel;
  final int? signalLevel;
  final int? bandwidth;
  final int? band;
  final bool? registered;
  final bool servingCellWasFallback;
  final List<CellTowerInfo> neighboringCells;

  OutdoorGpsBtsRecord({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.bearing,
    required this.provider,
    this.mcc,
    this.mnc,
    this.lac,
    this.tac,
    this.cellId,
    this.signalStrength,
    this.networkType,
    this.psc,
    this.pci,
    this.earfcn,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.cqi,
    this.timingAdvance,
    this.asuLevel,
    this.signalLevel,
    this.bandwidth,
    this.band,
    this.registered,
    this.servingCellWasFallback = false,
    this.neighboringCells = const <CellTowerInfo>[],
  });

  int? get eNodeBId {
    if (cellId == null || cellId! < 0) return null;
    if ((networkType ?? '').toUpperCase() != 'LTE') return null;
    return cellId! ~/ 256;
  }

  int? get localCellId {
    if (cellId == null || cellId! < 0) return null;
    if ((networkType ?? '').toUpperCase() != 'LTE') return null;
    return cellId! % 256;
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
    return <dynamic>[
      // Original columns — unchanged order.
      timestamp.toIso8601String(),
      latitude,
      longitude,
      altitude ?? '',
      accuracy ?? '',
      speed ?? '',
      bearing ?? '',
      provider,
      mcc ?? '',
      mnc ?? '',
      lac ?? '',
      tac ?? '',
      cellId ?? '',
      signalStrength ?? '',
      networkType ?? '',

      // Extended research columns.
      gpsQuality,
      eNodeBId ?? '',
      localCellId ?? '',
      psc ?? '',
      pci ?? '',
      earfcn ?? '',
      rsrp ?? '',
      rsrq ?? '',
      sinr ?? '',
      cqi ?? '',
      timingAdvance ?? '',
      asuLevel ?? '',
      signalLevel ?? '',
      bandwidth ?? '',
      band ?? '',
      registered ?? '',
      servingCellWasFallback,
      neighboringCells.length,
      jsonEncode(neighboringCells.map(_cellToJson).toList()),
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
      'rsrp': cell.rsrp,
      'rsrq': cell.rsrq,
      'sinr': cell.sinr,
      'cqi': cell.cqi,
      'timing_advance': cell.timingAdvance,
      'asu_level': cell.asuLevel,
      'signal_level': cell.level,
      'bandwidth': cell.bandwidth,
      'band': cell.band,
      'registered': cell.registered,
    };
  }

  static const List<String> csvHeader = <String>[
    // Original columns — unchanged order.
    'Timestamp',
    'Latitude',
    'Longitude',
    'Altitude',
    'Accuracy',
    'Speed',
    'Bearing',
    'Provider',
    'MCC',
    'MNC',
    'LAC',
    'TAC',
    'CellID',
    'SignalStrength',
    'NetworkType',

    // Extended research columns.
    'GpsQuality',
    'ENodeBID',
    'LocalCellID',
    'PSC',
    'PCI',
    'EARFCN',
    'RSRP',
    'RSRQ',
    'SINR',
    'CQI',
    'TimingAdvance',
    'ASULevel',
    'SignalLevel',
    'CellBandwidth',
    'Band',
    'Registered',
    'ServingCellWasFallback',
    'NeighborCellCount',
    'NeighborCellsJSON',
  ];
}
