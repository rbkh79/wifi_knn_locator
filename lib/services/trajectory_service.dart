/// سرویس مدیریت مسیر حرکت (Trajectory Service)
/// 
/// این سرویس برای مدیریت و پردازش مسیر حرکت کاربر طراحی شده است.
/// مسیر حرکت به صورت یک دنباله مکانی-زمانی از موقعیت‌های تخمینی ذخیره می‌شود.
/// 
/// عملکرد:
/// - ذخیره موقعیت‌های تخمینی به صورت زمانی
/// - هموارسازی مسیر با استفاده از فیلترهای ساده
/// - محاسبه سرعت و جهت حرکت
/// - مدیریت تاریخچه مسیر
/// 
/// چرا GPS-Free؟
/// - تمام موقعیت‌ها از Wi-Fi یا Cell-based localization به دست می‌آیند
/// - هیچ وابستگی به GPS یا سرویس‌های خارجی ندارد
/// - حریم خصوصی حفظ می‌شود (داده‌ها محلی هستند)
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';

/// نقطه در مسیر حرکت
class TrajectoryPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double confidence;
  final String? zoneLabel;
  final String environmentType; // 'indoor' یا 'outdoor'

  TrajectoryPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.confidence,
    this.zoneLabel,
    required this.environmentType,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'zone_label': zoneLabel,
      'environment_type': environmentType,
    };
  }

  factory TrajectoryPoint.fromMap(Map<String, dynamic> map) {
    return TrajectoryPoint(
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      timestamp: DateTime.parse(map['timestamp'] as String),
      confidence: map['confidence'] as double,
      zoneLabel: map['zone_label'] as String?,
      environmentType: map['environment_type'] as String? ?? 'unknown',
    );
  }
}

/// سرویس مدیریت مسیر حرکت
class TrajectoryService {
  final LocalDatabase _database;

  TrajectoryService(this._database);

  /// افزودن نقطه جدید به مسیر حرکت
  /// 
  /// این متد موقعیت تخمینی جدید را به تاریخچه مسیر اضافه می‌کند.
  /// 
  /// [estimate]: تخمین موقعیت از Indoor یا Outdoor localization
  /// [deviceId]: شناسه دستگاه
  /// [environmentType]: نوع محیط ('indoor' یا 'outdoor')
  Future<void> addTrajectoryPoint({
    required LocationEstimate estimate,
    required String deviceId,
    required String environmentType,
  }) async {
    try {
      // ذخیره در تاریخچه موقعیت
      await _database.insertLocationHistory(
        LocationHistoryEntry(
          deviceId: deviceId,
          latitude: estimate.latitude,
          longitude: estimate.longitude,
          zoneLabel: estimate.zoneLabel,
          confidence: estimate.confidence,
          timestamp: DateTime.now(),
        ),
      );

      debugPrint(
        'Trajectory point added: '
        '(${estimate.latitude.toStringAsFixed(6)}, ${estimate.longitude.toStringAsFixed(6)}), '
        'Env=$environmentType, '
        'Conf=${estimate.confidence.toStringAsFixed(2)}',
      );
    } catch (e) {
      debugPrint('Error adding trajectory point: $e');
    }
  }

  /// دریافت مسیر حرکت اخیر
  /// 
  /// این متد آخرین N نقطه از مسیر حرکت کاربر را برمی‌گرداند.
  /// 
  /// [deviceId]: شناسه دستگاه
  /// [limit]: حداکثر تعداد نقاط (پیش‌فرض: 50)
  /// 
  /// Returns: لیست نقاط مسیر به ترتیب زمانی (قدیمی‌ترین اول)
  Future<List<TrajectoryPoint>> getRecentTrajectory({
    required String deviceId,
    int limit = 50,
  }) async {
    try {
      final history = await _database.getLocationHistory(
        deviceId: deviceId,
        limit: limit,
        ascending: true, // قدیمی‌ترین اول
      );

      return history.map((entry) {
        // تعیین نوع محیط بر اساس confidence و zoneLabel
        // (این یک روش ساده است، می‌توان بهبود داد)
        final envType = entry.confidence > 0.5 ? 'indoor' : 'outdoor';

        return TrajectoryPoint(
          latitude: entry.latitude,
          longitude: entry.longitude,
          timestamp: entry.timestamp,
          confidence: entry.confidence,
          zoneLabel: entry.zoneLabel,
          environmentType: envType,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting trajectory: $e');
      return [];
    }
  }

  /// هموارسازی مسیر با استفاده از میانگین متحرک
  /// 
  /// این متد مسیر را با استفاده از یک فیلتر میانگین متحرک هموار می‌کند.
  /// این کار نویز و نوسانات کوچک را کاهش می‌دهد.
  /// 
  /// [trajectory]: مسیر خام
  /// [windowSize]: اندازه پنجره برای میانگین متحرک (پیش‌فرض: 3)
  /// 
  /// Returns: مسیر هموار شده
  List<TrajectoryPoint> smoothTrajectory(
    List<TrajectoryPoint> trajectory, {
    int windowSize = 3,
  }) {
    if (trajectory.length <= windowSize) {
      return trajectory; // اگر نقاط کافی نیست، هموارسازی نکن
    }

    final smoothed = <TrajectoryPoint>[];

    for (int i = 0; i < trajectory.length; i++) {
      if (i < windowSize ~/ 2 || i >= trajectory.length - windowSize ~/ 2) {
        // نقاط ابتدا و انتها را بدون تغییر نگه دار
        smoothed.add(trajectory[i]);
      } else {
        // محاسبه میانگین متحرک
        final window = trajectory.sublist(
          i - windowSize ~/ 2,
          i + windowSize ~/ 2 + 1,
        );

        final avgLat = window.map((p) => p.latitude).reduce((a, b) => a + b) /
            window.length;
        final avgLon = window.map((p) => p.longitude).reduce((a, b) => a + b) /
            window.length;
        final avgConf = window.map((p) => p.confidence).reduce((a, b) => a + b) /
            window.length;

        smoothed.add(TrajectoryPoint(
          latitude: avgLat,
          longitude: avgLon,
          timestamp: trajectory[i].timestamp,
          confidence: avgConf,
          zoneLabel: trajectory[i].zoneLabel,
          environmentType: trajectory[i].environmentType,
        ));
      }
    }

    return smoothed;
  }

  /// محاسبه سرعت حرکت از مسیر
  /// 
  /// این متد سرعت متوسط کاربر را از آخرین نقاط مسیر محاسبه می‌کند.
  /// 
  /// [trajectory]: مسیر حرکت
  /// 
  /// Returns: سرعت به متر بر ثانیه (m/s)
  double calculateSpeed(List<TrajectoryPoint> trajectory) {
    if (trajectory.length < 2) return 0.0;

    // استفاده از آخرین دو نقطه
    final last = trajectory.last;
    final previous = trajectory[trajectory.length - 2];

    final timeDiff = last.timestamp.difference(previous.timestamp).inSeconds;
    if (timeDiff == 0) return 0.0;

    // محاسبه فاصله (Haversine formula)
    final distance = _calculateDistance(
      previous.latitude,
      previous.longitude,
      last.latitude,
      last.longitude,
    );

    return distance / timeDiff; // متر بر ثانیه
  }

  /// محاسبه جهت حرکت از مسیر
  /// 
  /// این متد جهت حرکت کاربر را از آخرین نقاط مسیر محاسبه می‌کند.
  /// 
  /// [trajectory]: مسیر حرکت
  /// 
  /// Returns: جهت به رادیان (0 = شمال، π/2 = شرق)
  double calculateDirection(List<TrajectoryPoint> trajectory) {
    if (trajectory.length < 2) return 0.0;

    final last = trajectory.last;
    final previous = trajectory[trajectory.length - 2];

    final latDiff = last.latitude - previous.latitude;
    final lonDiff = last.longitude - previous.longitude;

    return math.atan2(latDiff, lonDiff);
  }

  /// محاسبه فاصله بین دو نقطه (Haversine formula)
  /// 
  /// این فرمول فاصله کروی بین دو نقطه جغرافیایی را محاسبه می‌کند.
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // متر

    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// پاک کردن مسیر قدیمی
  /// 
  /// این متد نقاط مسیر قدیمی‌تر از یک تاریخ مشخص را حذف می‌کند.
  /// 
  /// [deviceId]: شناسه دستگاه
  /// [beforeDate]: حذف نقاط قبل از این تاریخ
  Future<void> clearOldTrajectory({
    required String deviceId,
    required DateTime beforeDate,
  }) async {
    try {
      // این متد نیاز به پیاده‌سازی در LocalDatabase دارد
      // فعلاً فقط لاگ می‌کنیم
      debugPrint('Clearing trajectory before ${beforeDate.toIso8601String()}');
    } catch (e) {
      debugPrint('Error clearing trajectory: $e');
    }
  }
}

