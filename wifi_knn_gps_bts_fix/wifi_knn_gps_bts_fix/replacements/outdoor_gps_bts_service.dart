import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../cell_scanner.dart';
import '../data_model.dart';
import 'outdoor_csv_service.dart';

/// Continuous GPS + BTS recorder for outdoor research.
///
/// Reliability rules:
/// 1) A session CSV is created before recording starts.
/// 2) Every accepted sample is appended immediately with flush=true.
/// 3) Stop performs a final atomic rewrite/flush.
/// 4) LTE RSRP can safely fall back to Android's LTE getDbm() value.
///    RSRQ/SINR are never fabricated when the modem does not expose them.
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

  String? _currentSessionPath;
  String? _lastSavedPath;

  bool get isRecording => _isRecording;
  int get recordCount => _records.length;
  OutdoorGpsBtsRecord? get latestRecord =>
      _records.isEmpty ? null : _records.last;

  /// Current durable CSV file. It exists from the start of a recording.
  String? get currentSessionPath => _currentSessionPath;

  /// Most recently flushed/saved outdoor GPS+BTS CSV.
  String? get latestSavedPath => _lastSavedPath ?? _currentSessionPath;

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
      _lastSavedPath = null;

      // IMPORTANT: create persistent storage BEFORE collecting samples.
      _currentSessionPath = await OutdoorCsvService.createGpsBtsSessionFile();
      if (_currentSessionPath == null) {
        _notifyStatus('Could not create GPS+BTS session file. Recording not started.');
        return false;
      }

      _isRecording = true;
      _notifyStatus('Recording GPS+BTS; every sample is being saved...');

      // Capture first sample immediately.
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

  /// Stops capture and returns the final durable CSV path.
  ///
  /// Existing callers may ignore the returned value.
  Future<String?> stopRecording() async {
    debugPrint('[OutdoorBTS] Stop recording requested');

    if (!_isRecording) {
      // A second Stop should still expose/flush the previous session.
      return flushCurrentSession();
    }

    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    // Let an already-started sample finish its disk append.
    for (var i = 0; i < 80 && _captureInProgress; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (_records.isEmpty) {
      _notifyStatus('Recording stopped: no records were captured');
      return _currentSessionPath;
    }

    final filePath = await flushCurrentSession();
    if (filePath == null) {
      _notifyStatus(
        'WARNING: ${_records.length} records are in memory, but final file flush failed',
      );
      return null;
    }

    _lastSavedPath = filePath;
    _notifyStatus('Saved ${_records.length} GPS+BTS records');
    debugPrint('[OutdoorBTS] Final CSV: $filePath');
    return filePath;
  }

  /// Rewrites the current session from the in-memory records using a temporary
  /// file and rename, so Export can safely be called immediately after Stop.
  Future<String?> flushCurrentSession() async {
    if (_records.isEmpty) {
      final existing = _currentSessionPath;
      if (existing != null &&
          await OutdoorCsvService.gpsBtsFileExists(existing)) {
        _lastSavedPath = existing;
        return existing;
      }
      return null;
    }

    var path = _currentSessionPath;
    path ??= await OutdoorCsvService.createGpsBtsSessionFile();
    if (path == null) return null;

    final ok = await OutdoorCsvService.rewriteGpsBtsSession(
      path,
      _records,
    );

    if (!ok) return null;

    _currentSessionPath = path;
    _lastSavedPath = path;
    return path;
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
    // This check intentionally occurs before starting a radio scan. If Stop is
    // pressed after this point, the in-flight sample is still allowed to finish
    // and be durably written; stopRecording waits for _captureInProgress.
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

    // WRITE-THROUGH persistence: do not wait until Stop.
    var persisted = false;
    final path = _currentSessionPath;
    if (path != null) {
      persisted = await OutdoorCsvService.appendGpsBtsRecord(path, record);
    }

    // If append unexpectedly fails, immediately attempt a full recovery write.
    if (!persisted && _records.isNotEmpty) {
      debugPrint('[OutdoorBTS] Append failed; attempting session rewrite');
      final recoveredPath = await flushCurrentSession();
      persisted = recoveredPath != null;
    }

    _onRecordCountChanged?.call(_records.length);
    _onLatestRecordChanged?.call(record);

    final suffix = persisted ? 'saved' : 'SAVE WARNING';
    _notifyStatus(
      'GPS ±${position.accuracy.toStringAsFixed(0)} m | '
      'Cell ${record.cellId ?? '-'} | '
      'PCI ${record.pci ?? '-'} | '
      'RSRP ${record.effectiveRsrp ?? '-'} dBm | '
      '${record.neighboringCells.length} neighbors | $suffix',
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

  /// Compatibility/debug path. It now also uses write-through persistence.
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
      _onRecordCountChanged?.call(0);
      _lastSavedPath = null;
      _currentSessionPath = await OutdoorCsvService.createGpsBtsSessionFile();

      if (_currentSessionPath == null) {
        _notifyStatus('Could not create GPS-only session file');
        return false;
      }

      _isRecording = true;
      _notifyStatus('GPS-only test started; samples are saved immediately');

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

          final path = _currentSessionPath;
          var ok = false;
          if (path != null) {
            ok = await OutdoorCsvService.appendGpsBtsRecord(path, record);
          }
          if (!ok) {
            await flushCurrentSession();
          }

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

  /// Android's CellSignalStrengthLte.getDbm() is LTE RSRP. Therefore, when
  /// direct getRsrp() is unavailable but the LTE dBm value is valid, this is a
  /// legitimate RSRP fallback rather than an estimated/fabricated metric.
  int? get effectiveRsrp {
    if (rsrp != null) return rsrp;

    if ((networkType ?? '').toUpperCase() == 'LTE') {
      final value = signalStrength;
      if (value != null && value >= -160 && value <= -30) {
        return value;
      }
    }

    return null;
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
      // Original columns.
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

      // Store legitimate LTE getDbm() fallback when direct RSRP is unavailable.
      effectiveRsrp ?? '',

      // Never fabricate RSRQ/SINR. Blank means unavailable from device/modem.
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
    final type = (cell.networkType ?? '').toUpperCase();
    final effectiveNeighborRsrp =
        cell.rsrp ??
        (type == 'LTE' &&
                cell.signalStrength != null &&
                cell.signalStrength! >= -160 &&
                cell.signalStrength! <= -30
            ? cell.signalStrength
            : null);

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
      'rsrp': effectiveNeighborRsrp,
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
