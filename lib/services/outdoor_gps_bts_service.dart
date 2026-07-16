import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../cell_scanner.dart';
import '../data_model.dart';
import '../utils/privacy_utils.dart';
import 'outdoor_csv_service.dart';

/// سرویس ضبط پیوسته GPS + BTS برای Outdoor Positioning
/// 
/// این سرویس داده‌های GPS و BTS را به صورت پیوسته در حین حرکت خودرو ذخیره می‌کند
/// و داده‌ها را در فایل CSV جداگانه ذخیره می‌کند
class OutdoorGpsBtsService {
  static OutdoorGpsBtsService? _instance;
  static OutdoorGpsBtsService get instance {
    _instance ??= OutdoorGpsBtsService._internal();
    return _instance!;
  }

  OutdoorGpsBtsService._internal();

  // وضعیت ضبط
  bool _isRecording = false;
  Timer? _recordingTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  
  // داده‌های ذخیره شده
  final List<OutdoorGpsBtsRecord> _records = [];
  
  // تنظیمات ضبط
  static const Duration _samplingInterval = Duration(seconds: 1); // 1 ثانیه
  static const Duration _gpsUpdateInterval = Duration(seconds: 1); // 1 ثانیه
  
  // Callback برای به‌روزرسانی UI
  Function(int recordCount)? _onRecordCountChanged;
  Function(String status)? _onStatusChanged;

  /// آیا در حال ضبط است؟
  bool get isRecording => _isRecording;
  
  /// تعداد رکوردهای ذخیره شده
  int get recordCount => _records.length;

  /// شروع ضبط GPS + BTS
  Future<bool> startRecording({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
  }) async {
    debugPrint('[DEBUG] GPS+BTS Recording Start Request');
    if (_isRecording) {
      debugPrint('Outdoor GPS+BTS recording already in progress');
      return false;
    }

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;

    try {
      // بررسی مجوزهای GPS
      debugPrint('[DEBUG] Checking GPS service enabled...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('[DEBUG] GPS service enabled: $serviceEnabled');
      if (!serviceEnabled) {
        _notifyStatus('GPS service is disabled');
        return false;
      }

      debugPrint('[DEBUG] Checking GPS permission...');
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('[DEBUG] GPS permission status: $permission');
      if (permission == LocationPermission.denied) {
        debugPrint('[DEBUG] Requesting GPS permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('[DEBUG] GPS permission after request: $permission');
        if (permission == LocationPermission.denied) {
          _notifyStatus('GPS permission denied');
          return false;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _notifyStatus('GPS permission permanently denied');
        return false;
      }

      // بررسی مجوز BTS
      debugPrint('[DEBUG] Checking BTS permissions...');
      final hasBtsPermission = await CellScanner.checkPermissions();
      debugPrint('[DEBUG] BTS permissions granted: $hasBtsPermission');
      if (!hasBtsPermission) {
        debugPrint('[DEBUG] Requesting BTS permissions...');
        final granted = await CellScanner.requestPermissions();
        debugPrint('[DEBUG] BTS permissions after request: $granted');
        if (!granted) {
          _notifyStatus('BTS permission denied');
          return false;
        }
      }

      // پاک کردن رکوردهای قبلی
      _records.clear();
      debugPrint('[DEBUG] Cleared previous records');
      
      // شروع ضبط
      _isRecording = true;
      _notifyStatus('Recording started');
      debugPrint('[DEBUG] Recording started');
      
      // استفاده از تایمر برای ضبط GPS + BTS
      debugPrint('[DEBUG] Starting timer-based GPS+BTS polling (every 1 second)...');
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!_isRecording) {
          debugPrint('[DEBUG] Timer cancelled - not recording');
          timer.cancel();
          return;
        }
        
        debugPrint('[DEBUG] ===== Timer tick - Getting GPS position =====');
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
          debugPrint('[DEBUG] GPS position obtained: lat=${position.latitude}, lng=${position.longitude}');
          await _onPositionUpdate(position);
        } catch (e) {
          debugPrint('[DEBUG] GPS polling error: $e');
        }
      });

      debugPrint('[DEBUG] GPS+BTS timer started');
      debugPrint('[DEBUG] Outdoor GPS+BTS recording started successfully');
      return true;
    } catch (e) {
      debugPrint('[DEBUG] Error starting GPS+BTS recording: $e');
      _notifyStatus('Error: $e');
      _isRecording = false;
      return false;
    }
  }

  /// توقف ضبط
  Future<void> stopRecording() async {
    debugPrint('[DEBUG] GPS+BTS Recording Stop Request');
    if (!_isRecording) {
      debugPrint('[DEBUG] Not recording, nothing to stop');
      return;
    }

    _isRecording = false;
    debugPrint('[DEBUG] Recording flag set to false');
    
    // توقف استریم GPS
    debugPrint('[DEBUG] Cancelling GPS position stream...');
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    debugPrint('[DEBUG] GPS stream cancelled');
    
    // توقف تایمر
    _recordingTimer?.cancel();
    _recordingTimer = null;

    // ذخیره نهایی در CSV
    debugPrint('[DEBUG] Total records collected: ${_records.length}');
    if (_records.isNotEmpty) {
      debugPrint('[DEBUG] Saving records to CSV...');
      final filePath = await OutdoorCsvService.saveGpsBtsRecords(_records);
      debugPrint('[DEBUG] CSV saved to: $filePath');
      _notifyStatus('Saved ${_records.length} records to CSV');
    } else {
      debugPrint('[DEBUG] WARNING: No records to save!');
      _notifyStatus('No records to save');
    }

    debugPrint('[DEBUG] Outdoor GPS+BTS recording stopped. Total records: ${_records.length}');
  }

  /// هندلر آپدیت موقعیت GPS
  Future<void> _onPositionUpdate(Position position) async {
    if (!_isRecording) {
      debugPrint('[DEBUG] Ignoring GPS update - not recording');
      return;
    }

    debugPrint('[DEBUG] ===== Processing GPS Update =====');
    debugPrint('[DEBUG] GPS update:');
    debugPrint('[DEBUG]   Latitude: ${position.latitude}');
    debugPrint('[DEBUG]   Longitude: ${position.longitude}');
    debugPrint('[DEBUG]   Altitude: ${position.altitude}');
    debugPrint('[DEBUG]   Accuracy: ${position.accuracy}');
    debugPrint('[DEBUG]   Speed: ${position.speed}');
    debugPrint('[DEBUG]   Timestamp: ${position.timestamp}');

    try {
      // اسکن BTS به صورت موازی
      debugPrint('[DEBUG] BTS scan started');
      CellScanResult? cellScanResult;
      try {
        cellScanResult = await CellScanner.performScan();
        debugPrint('[DEBUG] BTS data received:');
        debugPrint('[DEBUG]   Serving cell: ${cellScanResult?.servingCell != null}');
        debugPrint('[DEBUG]   Neighboring cells: ${cellScanResult?.neighboringCells.length ?? 0}');
        if (cellScanResult?.servingCell != null) {
          debugPrint('[DEBUG]   BTS Cell ID: ${cellScanResult!.servingCell!.cellId}');
          debugPrint('[DEBUG]   BTS Signal Strength: ${cellScanResult.servingCell!.signalStrength}');
          debugPrint('[DEBUG]   BTS MCC: ${cellScanResult.servingCell!.mcc}');
          debugPrint('[DEBUG]   BTS MNC: ${cellScanResult.servingCell!.mnc}');
          debugPrint('[DEBUG]   BTS LAC/TAC: ${cellScanResult.servingCell!.lac ?? cellScanResult.servingCell!.tac}');
        }
      } catch (e) {
        debugPrint('[DEBUG] BTS scan error: $e');
        // ادامه با GPS فقط
      }

      // دریافت deviceId
      final deviceId = await PrivacyUtils.getDeviceId();

      // انتخاب دکل serving برای ذخیره
      CellTowerInfo? servingCell = cellScanResult?.servingCell;
      if (servingCell == null && cellScanResult?.neighboringCells.isNotEmpty == true) {
        servingCell = cellScanResult!.neighboringCells.first;
        debugPrint('Using neighboring cell as serving: ${servingCell.cellId}');
      }

      // ایجاد رکورد
      final record = OutdoorGpsBtsRecord(
        timestamp: DateTime.now(),
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
      );

      _records.add(record);
      debugPrint('[DEBUG] Saving CSV row:');
      debugPrint('[DEBUG]   Record count: ${_records.length}');
      debugPrint('[DEBUG]   Record data: ${record.toCsvRow()}');
      
      // به‌روزرسانی UI
      _onRecordCountChanged?.call(_records.length);
      
      debugPrint('[DEBUG] CSV write successful (in-memory)');
      debugPrint('[DEBUG] GPS+BTS record saved: ${record.latitude}, ${record.longitude}, BTS: ${servingCell?.cellId}');
    } catch (e) {
      debugPrint('[DEBUG] Error processing GPS update: $e');
    }
  }

  /// اطلاع‌رسانی وضعیت
  void _notifyStatus(String status) {
    _onStatusChanged?.call(status);
    debugPrint('[DEBUG] Outdoor GPS+BTS Status: $status');
  }

  /// پاک کردن رکوردها (بدون ذخیره)
  void clearRecords() {
    _records.clear();
    _onRecordCountChanged?.call(0);
  }

  /// تست ساده GPS-only با تایمر (بدون وابستگی به BTS)
  /// این متد برای عیب‌یابی استفاده می‌شود
  Future<bool> startGpsOnlyTest({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
  }) async {
    debugPrint('[DEBUG] ===== GPS-Only Test Start =====');
    if (_isRecording) {
      debugPrint('[DEBUG] Already recording, stop first');
      return false;
    }

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;

    try {
      // بررسی مجوز GPS
      debugPrint('[DEBUG] Checking GPS service enabled...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('[DEBUG] GPS service enabled: $serviceEnabled');
      if (!serviceEnabled) {
        _notifyStatus('GPS service is disabled');
        return false;
      }

      debugPrint('[DEBUG] Checking GPS permission...');
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('[DEBUG] GPS permission status: $permission');
      if (permission == LocationPermission.denied) {
        debugPrint('[DEBUG] Requesting GPS permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('[DEBUG] GPS permission after request: $permission');
        if (permission == LocationPermission.denied) {
          _notifyStatus('GPS permission denied');
          return false;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _notifyStatus('GPS permission permanently denied');
        return false;
      }

      // پاک کردن رکوردهای قبلی
      _records.clear();
      debugPrint('[DEBUG] Cleared previous records');
      
      // شروع ضبط
      _isRecording = true;
      _notifyStatus('GPS-Only test started');
      debugPrint('[DEBUG] GPS-Only test started');
      
      // استفاده از تایمر به جای استریم برای تست
      debugPrint('[DEBUG] Starting timer-based GPS polling (every 5 seconds)...');
      _recordingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (!_isRecording) {
          debugPrint('[DEBUG] Timer cancelled - not recording');
          timer.cancel();
          return;
        }
        
        debugPrint('[DEBUG] ===== Timer tick - Getting GPS position =====');
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
          debugPrint('[DEBUG] GPS position obtained: lat=${position.latitude}, lng=${position.longitude}');
          
          // ایجاد رکورد GPS-only
          final record = OutdoorGpsBtsRecord(
            timestamp: DateTime.now(),
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude,
            accuracy: position.accuracy,
            speed: position.speed,
            bearing: position.heading,
            provider: 'GPS',
            mcc: null,
            mnc: null,
            lac: null,
            tac: null,
            cellId: null,
            signalStrength: null,
            networkType: null,
          );

          _records.add(record);
          debugPrint('[DEBUG] GPS-Only record saved:');
          debugPrint('[DEBUG]   Record count: ${_records.length}');
          debugPrint('[DEBUG]   Record data: ${record.toCsvRow()}');
          
          _onRecordCountChanged?.call(_records.length);
          debugPrint('[DEBUG] GPS-Only CSV write successful (in-memory)');
        } catch (e) {
          debugPrint('[DEBUG] GPS-Only test error getting position: $e');
        }
      });

      debugPrint('[DEBUG] GPS-Only test timer started');
      return true;
    } catch (e) {
      debugPrint('[DEBUG] Error starting GPS-Only test: $e');
      _notifyStatus('Error: $e');
      _isRecording = false;
      return false;
    }
  }
}

/// مدل داده برای رکورد GPS + BTS
class OutdoorGpsBtsRecord {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final String provider;
  
  // BTS fields
  final int? mcc;
  final int? mnc;
  final int? lac;
  final int? tac;
  final int? cellId;
  final int? signalStrength;
  final String? networkType;

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
  });

  /// تبدیل به لیست برای CSV
  List<dynamic> toCsvRow() {
    return [
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
    ];
  }

  /// Header CSV
  static List<String> get csvHeader => [
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
  ];
}
