import 'dart:math' as math;
import '../data_model.dart';
import '../local_database.dart';

/// سرویس پیش‌بینی مسیر (Trajectory Prediction) بر اساس تاریخچه موقعیت
/// 
/// این سرویس بدون استفاده از GPS، مسیر آینده کاربر را بر اساس:
/// 1. تاریخچه موقعیت‌های ذخیره شده در SQLite
/// 2. الگوهای حرکت (velocity, direction)
/// 3. الگوهای زمانی (time-based patterns)
/// پیش‌بینی می‌کند
class TrajectoryPredictionService {
  final LocalDatabase _database;

  TrajectoryPredictionService(this._database);

  /// پیش‌بینی مسیر آینده بر اساس تاریخچه
  /// 
  /// [deviceId]: شناسه دستگاه
  /// [steps]: تعداد گام‌های آینده برای پیش‌بینی (پیش‌فرض: 5)
  /// [timeStepSeconds]: فاصله زمانی بین هر گام به ثانیه (پیش‌فرض: 5)
  /// 
  /// Returns: لیست موقعیت‌های پیش‌بینی شده
  Future<List<TrajectoryPoint>> predictTrajectory({
    required String deviceId,
    int steps = 5,
    int timeStepSeconds = 5,
  }) async {
    // دریافت تاریخچه موقعیت‌های اخیر
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 50,
      ascending: false, // جدیدترین اول
    );

    if (history.length < 2) {
      // اگر تاریخچه کافی نیست، موقعیت فعلی را برمی‌گردانیم
      if (history.isEmpty) {
        return [];
      }
      return List.generate(steps, (i) => TrajectoryPoint(
        latitude: history.first.latitude,
        longitude: history.first.longitude,
        timestamp: DateTime.now().add(Duration(seconds: (i + 1) * timeStepSeconds)),
        confidence: 0.1,
      ));
    }

    // محاسبه سرعت و جهت حرکت از آخرین موقعیت‌ها
    final velocity = _calculateVelocity(history);
    final direction = _calculateDirection(history);

    // پیش‌بینی مسیر با استفاده از سرعت و جهت
    final predictions = <TrajectoryPoint>[];
    final lastLocation = history.first;
    final lastTimestamp = lastLocation.timestamp;

    for (int i = 1; i <= steps; i++) {
      final timeDelta = Duration(seconds: i * timeStepSeconds);
      final predictedTimestamp = lastTimestamp.add(timeDelta);

      // محاسبه موقعیت پیش‌بینی شده
      final predictedLat = lastLocation.latitude + velocity.latVelocity * i * timeStepSeconds;
      final predictedLon = lastLocation.longitude + velocity.lonVelocity * i * timeStepSeconds;

      // کاهش confidence با افزایش فاصله زمانی
      final confidence = (lastLocation.confidence * math.pow(0.85, i)).clamp(0.05, 0.8);

      predictions.add(TrajectoryPoint(
        latitude: predictedLat,
        longitude: predictedLon,
        timestamp: predictedTimestamp,
        confidence: confidence,
        zoneLabel: lastLocation.zoneLabel,
      ));
    }

    return predictions;
  }

  /// محاسبه سرعت حرکت از تاریخچه
  _Velocity _calculateVelocity(List<LocationHistoryEntry> history) {
    if (history.length < 2) {
      return _Velocity(latVelocity: 0.0, lonVelocity: 0.0);
    }

    // استفاده از چند نقطه اخیر برای محاسبه سرعت متوسط
    final recentCount = math.min(5, history.length);
    double totalLatVelocity = 0.0;
    double totalLonVelocity = 0.0;
    int validPairs = 0;

    for (int i = 0; i < recentCount - 1; i++) {
      final current = history[i];
      final previous = history[i + 1];

      final timeDiff = current.timestamp.difference(previous.timestamp).inSeconds;
      if (timeDiff > 0) {
        final latDiff = current.latitude - previous.latitude;
        final lonDiff = current.longitude - previous.longitude;

        totalLatVelocity += latDiff / timeDiff;
        totalLonVelocity += lonDiff / timeDiff;
        validPairs++;
      }
    }

    if (validPairs == 0) {
      return _Velocity(latVelocity: 0.0, lonVelocity: 0.0);
    }

    return _Velocity(
      latVelocity: totalLatVelocity / validPairs,
      lonVelocity: totalLonVelocity / validPairs,
    );
  }

  /// محاسبه جهت حرکت از تاریخچه
  double _calculateDirection(List<LocationHistoryEntry> history) {
    if (history.length < 2) {
      return 0.0;
    }

    final current = history[0];
    final previous = history[1];

    final latDiff = current.latitude - previous.latitude;
    final lonDiff = current.longitude - previous.longitude;

    // محاسبه زاویه بر حسب رادیان
    return math.atan2(latDiff, lonDiff);
  }

  /// پیش‌بینی مسیر با در نظر گیری الگوهای تکراری
  /// 
  /// این متد سعی می‌کند الگوهای تکراری در تاریخچه را شناسایی کند
  /// و بر اساس آن مسیر را پیش‌بینی کند
  Future<List<TrajectoryPoint>> predictTrajectoryWithPatterns({
    required String deviceId,
    int steps = 5,
    int timeStepSeconds = 5,
  }) async {
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 200, // تاریخچه بیشتر برای شناسایی الگو
      ascending: false,
    );

    if (history.length < 10) {
      // اگر تاریخچه کافی نیست، از روش ساده استفاده می‌کنیم
      return predictTrajectory(
        deviceId: deviceId,
        steps: steps,
        timeStepSeconds: timeStepSeconds,
      );
    }

    // جستجوی الگوهای تکراری در تاریخچه
    final pattern = _findRepeatingPattern(history);
    
    if (pattern != null && pattern.length > 0) {
      // استفاده از الگوی تکراری برای پیش‌بینی
      return _predictFromPattern(pattern, history.first, steps, timeStepSeconds);
    }

    // اگر الگویی پیدا نشد، از روش ساده استفاده می‌کنیم
    return predictTrajectory(
      deviceId: deviceId,
      steps: steps,
      timeStepSeconds: timeStepSeconds,
    );
  }

  /// جستجوی الگوی تکراری در تاریخچه
  List<LocationHistoryEntry>? _findRepeatingPattern(List<LocationHistoryEntry> history) {
    // الگوریتم ساده: جستجوی دنباله‌های مشابه
    final minPatternLength = 3;
    final maxPatternLength = 10;

    for (int patternLen = minPatternLength; patternLen <= maxPatternLength; patternLen++) {
      if (history.length < patternLen * 2) continue;

      // بررسی اینکه آیا الگوی طول patternLen تکرار شده است
      for (int start = 0; start <= history.length - patternLen * 2; start++) {
        final pattern1 = history.sublist(start, start + patternLen);
        final pattern2 = history.sublist(start + patternLen, start + patternLen * 2);

        if (_patternsSimilar(pattern1, pattern2)) {
          return pattern1;
        }
      }
    }

    return null;
  }

  /// بررسی شباهت دو الگو
  bool _patternsSimilar(
    List<LocationHistoryEntry> pattern1,
    List<LocationHistoryEntry> pattern2,
  ) {
    if (pattern1.length != pattern2.length) return false;

    const threshold = 0.001; // حدود 100 متر

    for (int i = 0; i < pattern1.length; i++) {
      final latDiff = (pattern1[i].latitude - pattern2[i].latitude).abs();
      final lonDiff = (pattern1[i].longitude - pattern2[i].longitude).abs();

      if (latDiff > threshold || lonDiff > threshold) {
        return false;
      }
    }

    return true;
  }

  /// پیش‌بینی بر اساس الگوی تکراری
  List<TrajectoryPoint> _predictFromPattern(
    List<LocationHistoryEntry> pattern,
    LocationHistoryEntry lastLocation,
    int steps,
    int timeStepSeconds,
  ) {
    final predictions = <TrajectoryPoint>[];
    final now = DateTime.now();

    // محاسبه فاصله زمانی متوسط در الگو
    if (pattern.length > 1) {
      final avgTimeDiff = pattern[0].timestamp
          .difference(pattern[pattern.length - 1].timestamp)
          .inSeconds /
          (pattern.length - 1);
      
      // استفاده از الگو برای پیش‌بینی
      for (int i = 1; i <= steps; i++) {
        // انتخاب نقطه از الگو (با چرخش)
        final patternIndex = (i - 1) % pattern.length;
        final patternPoint = pattern[patternIndex];

        // محاسبه offset از آخرین موقعیت
        final latOffset = patternPoint.latitude - pattern.first.latitude;
        final lonOffset = patternPoint.longitude - pattern.first.longitude;

        final predictedLat = lastLocation.latitude + latOffset;
        final predictedLon = lastLocation.longitude + lonOffset;
        final predictedTimestamp = now.add(Duration(seconds: i * timeStepSeconds));

        // کاهش confidence با افزایش فاصله
        final confidence = (lastLocation.confidence * math.pow(0.8, i)).clamp(0.1, 0.7);

        predictions.add(TrajectoryPoint(
          latitude: predictedLat,
          longitude: predictedLon,
          timestamp: predictedTimestamp,
          confidence: confidence,
          zoneLabel: patternPoint.zoneLabel ?? lastLocation.zoneLabel,
        ));
      }
    }

    return predictions;
  }
}

/// کلاس برای نگهداری سرعت حرکت
class _Velocity {
  final double latVelocity; // سرعت در جهت latitude (درجه بر ثانیه)
  final double lonVelocity; // سرعت در جهت longitude (درجه بر ثانیه)

  _Velocity({
    required this.latVelocity,
    required this.lonVelocity,
  });
}

/// نقطه در مسیر پیش‌بینی شده
class TrajectoryPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double confidence;
  final String? zoneLabel;

  TrajectoryPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.confidence,
    this.zoneLabel,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'zone_label': zoneLabel,
    };
  }

  factory TrajectoryPoint.fromMap(Map<String, dynamic> map) {
    return TrajectoryPoint(
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      timestamp: DateTime.parse(map['timestamp'] as String),
      confidence: map['confidence'] as double,
      zoneLabel: map['zone_label'] as String?,
    );
  }
}

