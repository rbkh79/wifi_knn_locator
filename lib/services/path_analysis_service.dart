import 'dart:math' as math;
import '../data_model.dart';
import '../local_database.dart';
import '../utils/privacy_utils.dart';

/// سرویس تحلیل مسیر حرکت کاربر
class PathAnalysisService {
  final LocalDatabase _database;

  PathAnalysisService(this._database);

  /// محاسبه کل طول مسیر یک کاربر (به متر)
  Future<double> calculateTotalPathLength(String deviceId) async {
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 99999,
      ascending: true, // مرتب‌سازی بر اساس زمان
    );

    if (history.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 0; i < history.length - 1; i++) {
      final current = history[i];
      final next = history[i + 1];
      final distance = _calculateHaversineDistance(
        current.latitude,
        current.longitude,
        next.latitude,
        next.longitude,
      );
      totalDistance += distance;
    }

    return totalDistance;
  }

  /// محاسبه فاصله بین دو نقطه (به متر) - فرمول Haversine
  double _calculateHaversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // متر

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  /// دریافت تاریخچه مسیر یک کاربر (مرتب شده بر اساس زمان)
  Future<List<LocationHistoryEntry>> getUserPath(String deviceId) async {
    return await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 99999,
      ascending: true,
    );
  }

  /// محاسبه سرعت متوسط حرکت (متر بر ثانیه)
  Future<double?> calculateAverageSpeed(String deviceId) async {
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 99999,
      ascending: true,
    );

    if (history.length < 2) return null;

    double totalDistance = 0.0;
    int totalTimeSeconds = 0;

    for (int i = 0; i < history.length - 1; i++) {
      final current = history[i];
      final next = history[i + 1];

      final distance = _calculateHaversineDistance(
        current.latitude,
        current.longitude,
        next.latitude,
        next.longitude,
      );
      totalDistance += distance;

      final timeDiff = next.timestamp.difference(current.timestamp).inSeconds;
      if (timeDiff > 0) {
        totalTimeSeconds += timeDiff;
      }
    }

    if (totalTimeSeconds == 0) return null;
    return totalDistance / totalTimeSeconds;
  }

  /// محاسبه مدت زمان حضور در یک منطقه (به ثانیه)
  Future<Map<String, int>> calculateZonePresenceTime(String deviceId) async {
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 99999,
      ascending: true,
    );

    if (history.isEmpty) return {};

    final zoneTimes = <String, int>{};
    String? currentZone;
    DateTime? zoneStartTime;

    for (final entry in history) {
      final zone = entry.zoneLabel ?? 'نامشخص';
      
      if (currentZone == null || currentZone != zone) {
        // اگر منطقه تغییر کرد، زمان حضور قبلی را ثبت کن
        if (currentZone != null && zoneStartTime != null) {
          final duration = entry.timestamp.difference(zoneStartTime).inSeconds;
          zoneTimes[currentZone] = (zoneTimes[currentZone] ?? 0) + duration;
        }
        
        // شروع منطقه جدید
        currentZone = zone;
        zoneStartTime = entry.timestamp;
      }
    }

    // آخرین منطقه
    if (currentZone != null && zoneStartTime != null && history.isNotEmpty) {
      final lastEntry = history.last;
      final duration = lastEntry.timestamp.difference(zoneStartTime).inSeconds;
      zoneTimes[currentZone] = (zoneTimes[currentZone] ?? 0) + duration;
    }

    return zoneTimes;
  }

  /// پیدا کردن نزدیک‌ترین نقطه روی مسیر به یک مختصات
  /// بازگرداندن: فاصله (متر) و شاخص نقطه روی مسیر
  Future<Map<String, dynamic>> findNearestPointOnPath(
    String deviceId,
    double targetLat,
    double targetLon,
  ) async {
    final path = await getUserPath(deviceId);

    if (path.isEmpty) {
      return {'distance': null, 'index': null, 'point': null};
    }

    double minDistance = double.infinity;
    int nearestIndex = 0;

    for (int i = 0; i < path.length; i++) {
      final entry = path[i];
      final distance = _calculateHaversineDistance(
        targetLat,
        targetLon,
        entry.latitude,
        entry.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }

    return {
      'distance': minDistance,
      'index': nearestIndex,
      'point': path[nearestIndex],
    };
  }

  /// محاسبه آمار مسیر (طول کل، زمان کل، تعداد نقاط)
  Future<Map<String, dynamic>> getPathStatistics(String deviceId) async {
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 99999,
      ascending: true,
    );

    if (history.isEmpty) {
      return {
        'total_points': 0,
        'total_distance_meters': 0.0,
        'total_time_seconds': 0,
        'average_speed_ms': null,
        'start_time': null,
        'end_time': null,
      };
    }

    final totalDistance = await calculateTotalPathLength(deviceId);
    final startTime = history.first.timestamp;
    final endTime = history.last.timestamp;
    final totalTimeSeconds = endTime.difference(startTime).inSeconds;
    final averageSpeed = totalTimeSeconds > 0
        ? totalDistance / totalTimeSeconds
        : null;

    return {
      'total_points': history.length,
      'total_distance_meters': totalDistance,
      'total_time_seconds': totalTimeSeconds,
      'average_speed_ms': averageSpeed,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
    };
  }
}


