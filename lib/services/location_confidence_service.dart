import 'dart:math' as math;
import '../data_model.dart';
import '../local_database.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/privacy_utils.dart';

/// نتیجه بررسی اطمینان موقعیت
class ConfidenceResult {
  final bool isReliable;
  final bool isNewLocation;
  final double confidenceScore;
  final String? warningMessage;
  final double? gpsKnnDistance; // فاصله بین GPS و KNN (به متر)

  ConfidenceResult({
    required this.isReliable,
    required this.isNewLocation,
    required this.confidenceScore,
    this.warningMessage,
    this.gpsKnnDistance,
  });
}

/// سرویس تشخیص اطمینان و مکان جدید
/// این سرویس بررسی می‌کند که آیا تخمین KNN قابل اعتماد است یا نه
class LocationConfidenceService {
  final LocalDatabase _database;

  LocationConfidenceService(this._database);

  /// بررسی اطمینان تخمین KNN
  /// 
  /// بررسی‌های انجام شده:
  /// 1. بررسی confidence score تخمین
  /// 2. بررسی فاصله تا نزدیک‌ترین همسایه
  /// 3. مقایسه GPS با KNN (اگر GPS در دسترس باشد)
  /// 4. بررسی تعداد APهای مشترک
  Future<ConfidenceResult> checkLocationConfidence({
    required LocationEstimate? knnEstimate,
    Position? gpsPosition,
    required WifiScanResult scanResult,
  }) async {
    // اگر تخمینی وجود ندارد، احتمالاً مکان جدید است
    if (knnEstimate == null) {
      return ConfidenceResult(
        isReliable: false,
        isNewLocation: true,
        confidenceScore: 0.0,
        warningMessage: 'تخمین موقعیت امکان‌پذیر نیست. احتمالاً در مکان جدیدی هستید.',
      );
    }

    double confidenceScore = knnEstimate.confidence;
    bool isReliable = true;
    bool isNewLocation = false;
    String? warningMessage;
    double? gpsKnnDistance;

    // 1. بررسی confidence score
    // اگر confidence کمتر از 0.3 باشد، تخمین غیرقابل اعتماد است
    if (confidenceScore < 0.3) {
      isReliable = false;
      isNewLocation = true;
      warningMessage = 'ضریب اطمینان پایین است (${(confidenceScore * 100).toStringAsFixed(1)}%). احتمالاً در مکان جدیدی هستید.';
    }

    // 2. بررسی فاصله تا نزدیک‌ترین همسایه
    // اگر فاصله بیش از 100 واحد باشد، احتمالاً مکان جدید است
    if (knnEstimate.averageDistance > 100) {
      isReliable = false;
      isNewLocation = true;
      warningMessage = 'فاصله تا نزدیک‌ترین نقاط مرجع زیاد است. احتمالاً در مکان جدیدی هستید.';
    }

    // 3. مقایسه GPS با KNN (اگر GPS در دسترس باشد)
    if (gpsPosition != null) {
      final distance = _calculateHaversineDistance(
        gpsPosition.latitude,
        gpsPosition.longitude,
        knnEstimate.latitude,
        knnEstimate.longitude,
      );

      gpsKnnDistance = distance;

      // اگر فاصله GPS و KNN بیش از 500 متر باشد، احتمالاً مکان جدید است
      if (distance > 500) {
        isReliable = false;
        isNewLocation = true;
        warningMessage = 'فاصله بین GPS ($distance.toStringAsFixed(0) متر) و تخمین KNN زیاد است. احتمالاً در مکان جدیدی هستید که قبلاً اثرانگشتی از آن ثبت نشده است.';
      } else if (distance > 100) {
        // هشدار برای فاصله متوسط
        if (warningMessage == null) {
          warningMessage = 'فاصله بین GPS و تخمین KNN نسبتاً زیاد است ($distance.toStringAsFixed(0) متر).';
        }
        confidenceScore *= 0.8; // کاهش confidence
      }
    }

    // 4. بررسی تعداد APهای مشترک
    if (knnEstimate.nearestNeighbors.isNotEmpty) {
      final nearestFingerprint = knnEstimate.nearestNeighbors.first;
      final commonAps = _countCommonAps(scanResult.accessPoints, nearestFingerprint.accessPoints);
      final totalAps = math.max(scanResult.accessPoints.length, nearestFingerprint.accessPoints.length);
      final overlapRatio = commonAps / totalAps;

      // اگر کمتر از 30% AP مشترک باشد، احتمالاً مکان جدید است
      if (overlapRatio < 0.3) {
        isReliable = false;
        isNewLocation = true;
        warningMessage = 'تعداد APهای مشترک کم است (${(overlapRatio * 100).toStringAsFixed(0)}%). احتمالاً در مکان جدیدی هستید.';
      } else if (overlapRatio < 0.5) {
        confidenceScore *= 0.9; // کاهش جزئی confidence
      }
    }

    // اگر هنوز reliable است اما confidence پایین است، غیرقابل اعتماد کنیم
    if (isReliable && confidenceScore < 0.5) {
      isReliable = false;
    }

    return ConfidenceResult(
      isReliable: isReliable,
      isNewLocation: isNewLocation,
      confidenceScore: confidenceScore,
      warningMessage: warningMessage,
      gpsKnnDistance: gpsKnnDistance,
    );
  }

  /// شمارش APهای مشترک
  int _countCommonAps(List<WifiReading> scanAps, List<WifiReading> fingerprintAps) {
    final scanBssids = scanAps.map((ap) => ap.bssid).toSet();
    final fingerprintBssids = fingerprintAps.map((ap) => ap.bssid).toSet();
    
    return scanBssids.intersection(fingerprintBssids).length;
  }

  /// محاسبه فاصله بین دو نقطه با استفاده از فرمول Haversine (به متر)
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
}

