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
    if (_isRecording) {
      debugPrint('Outdoor GPS+BTS recording already in progress');
      return false;
    }

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;

    try {
      // بررسی مجوزهای GPS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _notifyStatus('GPS service is disabled');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
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
      final hasBtsPermission = await CellScanner.checkPermissions();
      if (!hasBtsPermission) {
        final granted = await CellScanner.requestPermissions();
        if (!granted) {
          _notifyStatus('BTS permission denied');
          return false;
        }
      }

      // پاک کردن رکوردهای قبلی
      _records.clear();
      
      // شروع ضبط
      _isRecording = true;
      _notifyStatus('Recording started');
      
      // شروع استریم GPS
      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        forceLocationManager: false,
        interval: _gpsUpdateInterval.inMilliseconds,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Recording GPS+BTS data for outdoor positioning',
          notificationTitle: 'Outdoor Recording',
          enableWakeLock: true,
        ),
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _onPositionUpdate(position);
        },
        onError: (error) {
          debugPrint('GPS stream error: $error');
          _notifyStatus('GPS error: $error');
        },
      );

      debugPrint('Outdoor GPS+BTS recording started');
      return true;
    } catch (e) {
      debugPrint('Error starting GPS+BTS recording: $e');
      _notifyStatus('Error: $e');
      _isRecording = false;
      return false;
    }
  }

  /// توقف ضبط
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    
    // توقف استریم GPS
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    
    // توقف تایمر
    _recordingTimer?.cancel();
    _recordingTimer = null;

    // ذخیره نهایی در CSV
    if (_records.isNotEmpty) {
      await OutdoorCsvService.saveGpsBtsRecords(_records);
      _notifyStatus('Saved ${_records.length} records to CSV');
    } else {
      _notifyStatus('No records to save');
    }

    debugPrint('Outdoor GPS+BTS recording stopped. Total records: ${_records.length}');
  }

  /// هندلر آپدیت موقعیت GPS
  Future<void> _onPositionUpdate(Position position) async {
    if (!_isRecording) return;

    try {
      // اسکن BTS به صورت موازی
      CellScanResult? cellScanResult;
      try {
        cellScanResult = await CellScanner.performScan();
      } catch (e) {
        debugPrint('BTS scan error: $e');
        // ادامه با GPS فقط
      }

      // دریافت deviceId
      final deviceId = await PrivacyUtils.getDeviceId();

      // انتخاب دکل serving برای ذخیره
      CellTowerInfo? servingCell = cellScanResult?.servingCell;
      if (servingCell == null && cellScanResult?.neighboringCells.isNotEmpty == true) {
        servingCell = cellScanResult!.neighboringCells.first;
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
      
      // به‌روزرسانی UI
      _onRecordCountChanged?.call(_records.length);
      
      debugPrint('GPS+BTS record: ${record.latitude}, ${record.longitude}, BTS: ${servingCell?.cellId}');
    } catch (e) {
      debugPrint('Error processing GPS update: $e');
    }
  }

  /// اطلاع‌رسانی وضعیت
  void _notifyStatus(String status) {
    _onStatusChanged?.call(status);
    debugPrint('Outdoor GPS+BTS Status: $status');
  }

  /// پاک کردن رکوردها (بدون ذخیره)
  void clearRecords() {
    _records.clear();
    _onRecordCountChanged?.call(0);
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
