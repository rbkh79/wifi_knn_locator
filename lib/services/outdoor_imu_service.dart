import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'outdoor_csv_service.dart';

/// سرویس ضبط پیوسته IMU (Accelerometer + Gyroscope + Magnetometer) برای Outdoor Positioning
/// 
/// این سرویس داده‌های سنسورهای حرکتی را به صورت پیوسته در حین حرکت خودرو ذخیره می‌کند
/// و داده‌ها را در فایل CSV جداگانه ذخیره می‌کند
class OutdoorImuService {
  static OutdoorImuService? _instance;
  static OutdoorImuService get instance {
    _instance ??= OutdoorImuService._internal();
    return _instance!;
  }

  OutdoorImuService._internal();

  // وضعیت ضبط
  bool _isRecording = false;
  
  // استریم‌های سنسور
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  
  // داده‌های ذخیره شده
  final List<OutdoorImuRecord> _records = [];
  
  // تنظیمات ضبط
  static const Duration _samplingInterval = Duration(milliseconds: 100); // 10 Hz
  
  // داده‌های فعلی برای سینک کردن
  double? _currentAx, _currentAy, _currentAz;
  double? _currentGx, _currentGy, _currentGz;
  double? _currentMx, _currentMy, _currentMz;
  DateTime? _lastAccelerometerTime;
  DateTime? _lastGyroscopeTime;
  DateTime? _lastMagnetometerTime;
  
  // Callback برای به‌روزرسانی UI
  Function(int recordCount)? _onRecordCountChanged;
  Function(String status)? _onStatusChanged;

  /// آیا در حال ضبط است؟
  bool get isRecording => _isRecording;
  
  /// تعداد رکوردهای ذخیره شده
  int get recordCount => _records.length;

  /// شروع ضبط IMU
  Future<bool> startRecording({
    Function(int recordCount)? onRecordCountChanged,
    Function(String status)? onStatusChanged,
  }) async {
    if (_isRecording) {
      debugPrint('Outdoor IMU recording already in progress');
      return false;
    }

    _onRecordCountChanged = onRecordCountChanged;
    _onStatusChanged = onStatusChanged;

    try {
      // پاک کردن رکوردهای قبلی
      _records.clear();
      _clearCurrentData();
      
      // شروع ضبط
      _isRecording = true;
      _notifyStatus('Recording started');
      
      // شروع استریم Accelerometer
      _accelerometerSubscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(
        _onAccelerometerEvent,
        onError: (error) {
          debugPrint('Accelerometer stream error: $error');
        },
      );

      // شروع استریم Gyroscope
      _gyroscopeSubscription = gyroscopeEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(
        _onGyroscopeEvent,
        onError: (error) {
          debugPrint('Gyroscope stream error: $error');
        },
      );

      // شروع استریم Magnetometer (اختیاری)
      try {
        _magnetometerSubscription = magnetometerEventStream(
          samplingPeriod: SensorInterval.normalInterval,
        ).listen(
          _onMagnetometerEvent,
          onError: (error) {
            debugPrint('Magnetometer stream error: $error');
            // Magnetometer اختیاری است، خطا را نادیده می‌گیریم
          },
        );
      } catch (e) {
        debugPrint('Magnetometer not available: $e');
      }

      debugPrint('Outdoor IMU recording started');
      return true;
    } catch (e) {
      debugPrint('Error starting IMU recording: $e');
      _notifyStatus('Error: $e');
      _isRecording = false;
      return false;
    }
  }

  /// توقف ضبط
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    
    // توقف استریم‌ها
    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    
    await _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;
    
    await _magnetometerSubscription?.cancel();
    _magnetometerSubscription = null;

    // ذخیره نهایی در CSV
    if (_records.isNotEmpty) {
      await OutdoorCsvService.saveImuRecords(_records);
      _notifyStatus('Saved ${_records.length} records to CSV');
    } else {
      _notifyStatus('No records to save');
    }

    debugPrint('Outdoor IMU recording stopped. Total records: ${_records.length}');
  }

  /// هندلر رویداد Accelerometer
  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!_isRecording) return;

    _currentAx = event.x;
    _currentAy = event.y;
    _currentAz = event.z;
    _lastAccelerometerTime = DateTime.now();
    
    // تلاش برای سینک کردن و ذخیره رکورد
    _trySyncAndSave();
  }

  /// هندلر رویداد Gyroscope
  void _onGyroscopeEvent(GyroscopeEvent event) {
    if (!_isRecording) return;

    _currentGx = event.x;
    _currentGy = event.y;
    _currentGz = event.z;
    _lastGyroscopeTime = DateTime.now();
    
    // تلاش برای سینک کردن و ذخیره رکورد
    _trySyncAndSave();
  }

  /// هندلر رویداد Magnetometer
  void _onMagnetometerEvent(MagnetometerEvent event) {
    if (!_isRecording) return;

    _currentMx = event.x;
    _currentMy = event.y;
    _currentMz = event.z;
    _lastMagnetometerTime = DateTime.now();
    
    // تلاش برای سینک کردن و ذخیره رکورد
    _trySyncAndSave();
  }

  /// تلاش برای سینک کردن داده‌ها و ذخیره رکورد
  void _trySyncAndSave() {
    // فقط اگر Accelerometer و Gyroscope موجود باشند ذخیره می‌کنیم
    if (_currentAx == null || _currentGx == null) return;

    // استفاده از زمان Accelerometer به عنوان timestamp اصلی
    final timestamp = _lastAccelerometerTime ?? DateTime.now();
    
    // محاسبه فاصله زمانی از آخرین ذخیره (برای جلوگیری از ذخیره زیاد)
    if (_records.isNotEmpty) {
      final lastRecord = _records.last;
      final timeDiff = timestamp.difference(lastRecord.timestamp);
      if (timeDiff < _samplingInterval) {
        return; // هنوز زمان نرسیده
      }
    }

    // ایجاد رکورد
    final record = OutdoorImuRecord(
      timestamp: timestamp,
      ax: _currentAx!,
      ay: _currentAy!,
      az: _currentAz!,
      gx: _currentGx!,
      gy: _currentGy!,
      gz: _currentGz!,
      mx: _currentMx,
      my: _currentMy,
      mz: _currentMz,
      samplingIntervalMs: _samplingInterval.inMilliseconds,
    );

    _records.add(record);
    
    // به‌روزرسانی UI
    _onRecordCountChanged?.call(_records.length);
    
    debugPrint('IMU record: ax=${record.ax.toStringAsFixed(2)}, ay=${record.ay.toStringAsFixed(2)}, az=${record.az.toStringAsFixed(2)}');
  }

  /// پاک کردن داده‌های فعلی
  void _clearCurrentData() {
    _currentAx = null;
    _currentAy = null;
    _currentAz = null;
    _currentGx = null;
    _currentGy = null;
    _currentGz = null;
    _currentMx = null;
    _currentMy = null;
    _currentMz = null;
    _lastAccelerometerTime = null;
    _lastGyroscopeTime = null;
    _lastMagnetometerTime = null;
  }

  /// اطلاع‌رسانی وضعیت
  void _notifyStatus(String status) {
    _onStatusChanged?.call(status);
    debugPrint('Outdoor IMU Status: $status');
  }

  /// پاک کردن رکوردها (بدون ذخیره)
  void clearRecords() {
    _records.clear();
    _clearCurrentData();
    _onRecordCountChanged?.call(0);
  }
}

/// مدل داده برای رکورد IMU
class OutdoorImuRecord {
  final DateTime timestamp;
  final double ax; // Accelerometer X
  final double ay; // Accelerometer Y
  final double az; // Accelerometer Z
  final double gx; // Gyroscope X
  final double gy; // Gyroscope Y
  final double gz; // Gyroscope Z
  final double? mx; // Magnetometer X (اختیاری)
  final double? my; // Magnetometer Y (اختیاری)
  final double? mz; // Magnetometer Z (اختیاری)
  final int samplingIntervalMs; // فاصله نمونه‌برداری

  OutdoorImuRecord({
    required this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    this.mx,
    this.my,
    this.mz,
    required this.samplingIntervalMs,
  });

  /// تبدیل به لیست برای CSV
  List<dynamic> toCsvRow() {
    return [
      timestamp.toIso8601String(),
      ax.toStringAsFixed(6),
      ay.toStringAsFixed(6),
      az.toStringAsFixed(6),
      gx.toStringAsFixed(6),
      gy.toStringAsFixed(6),
      gz.toStringAsFixed(6),
      mx?.toStringAsFixed(6) ?? '',
      my?.toStringAsFixed(6) ?? '',
      mz?.toStringAsFixed(6) ?? '',
      samplingIntervalMs,
    ];
  }

  /// Header CSV
  static List<String> get csvHeader => [
    'Timestamp',
    'ax',
    'ay',
    'az',
    'gx',
    'gy',
    'gz',
    'mx',
    'my',
    'mz',
    'SamplingIntervalMs',
  ];
}
