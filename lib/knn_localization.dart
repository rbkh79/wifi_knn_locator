import 'dart:math' as math;
import 'data_model.dart';
import 'config.dart';
import 'local_database.dart';

/// پیاده‌سازی الگوریتم KNN برای تخمین موقعیت
class KnnLocalization {
  final LocalDatabase _database;

  KnnLocalization(this._database);

  /// تخمین موقعیت بر اساس اسکن Wi-Fi فعلی
  /// 
  /// الگوریتم:
  /// 1. بارگذاری تمام اثرانگشت‌ها از پایگاه داده
  /// 2. محاسبه فاصله بین اسکن فعلی و هر اثرانگشت
  /// 3. انتخاب k همسایه نزدیک
  /// 4. محاسبه موقعیت تخمینی با میانگین وزن‌دار
  /// 5. محاسبه ضریب اطمینان
  Future<LocationEstimate?> estimateLocation(
    WifiScanResult scanResult, {
    int k = AppConfig.defaultK,
  }) async {
    // بارگذاری اثرانگشت‌ها
    final fingerprints = await _database.getAllFingerprints();
    
    if (fingerprints.isEmpty) {
      return null;
    }

    // بررسی حداقل تعداد AP
    if (scanResult.accessPoints.length < AppConfig.minApCountForEvaluation) {
      return null;
    }

    // محاسبه فاصله‌ها
    final distances = <DistanceRecord>[];
    
    for (int i = 0; i < fingerprints.length; i++) {
      final fingerprint = fingerprints[i];
      final distance = _calculateDistance(scanResult.accessPoints, fingerprint.accessPoints);
      
      distances.add(DistanceRecord(
        distance: distance,
        fingerprint: fingerprint,
        index: i,
      ));
    }

    // مرتب‌سازی بر اساس فاصله
    distances.sort((a, b) => a.distance.compareTo(b.distance));

    // انتخاب k همسایه نزدیک
    final kNearest = k < distances.length ? k : distances.length;
    if (kNearest == 0) {
      return null;
    }

    final nearestNeighbors = distances.take(kNearest).map((d) => d.fingerprint).toList();
    final nearestDistances = distances.take(kNearest).map((d) => d.distance).toList();

    // محاسبه موقعیت تخمینی با میانگین وزن‌دار
    // وزن = 1 / (فاصله + 1) برای جلوگیری از تقسیم بر صفر
    double latSum = 0.0;
    double lonSum = 0.0;
    double weightSum = 0.0;

    for (int i = 0; i < nearestNeighbors.length; i++) {
      final neighbor = nearestNeighbors[i];
      final distance = nearestDistances[i];
      final weight = 1.0 / (distance + 1.0); // +1 برای جلوگیری از تقسیم بر صفر

      latSum += neighbor.latitude * weight;
      lonSum += neighbor.longitude * weight;
      weightSum += weight;
    }

    if (weightSum == 0) {
      return null;
    }

    final estimatedLat = latSum / weightSum;
    final estimatedLon = lonSum / weightSum;

    // محاسبه میانگین فاصله
    final avgDistance = nearestDistances.reduce((a, b) => a + b) / nearestDistances.length;

    // محاسبه ضریب اطمینان
    // اعتماد = 1 / (1 + میانگین فاصله) - نرمال‌سازی شده
    final confidence = _calculateConfidence(avgDistance, nearestDistances);

    // تعیین لیبل ناحیه (اگر اکثر همسایه‌ها یک لیبل داشته باشند)
    final zoneLabel = _determineZoneLabel(nearestNeighbors);

    return LocationEstimate(
      latitude: estimatedLat,
      longitude: estimatedLon,
      confidence: confidence,
      zoneLabel: zoneLabel,
      nearestNeighbors: nearestNeighbors,
      averageDistance: avgDistance,
    );
  }

  /// محاسبه فاصله بین دو بردار Wi-Fi
  /// 
  /// از فاصله اقلیدسی استفاده می‌کند:
  /// - برای هر BSSID مشترک: (RSSI1 - RSSI2)²
  /// - برای BSSID‌های غیرمشترک: مقدار پیش‌فرض (-100) استفاده می‌شود
  double _calculateDistance(List<WifiReading> observed, List<WifiReading> fingerprint) {
    // ساخت Map برای دسترسی سریع‌تر
    final observedMap = <String, int>{};
    for (final ap in observed) {
      observedMap[ap.bssid] = ap.rssi;
    }

    final fingerprintMap = <String, int>{};
    for (final ap in fingerprint) {
      fingerprintMap[ap.bssid] = ap.rssi;
    }

    // جمع‌آوری تمام BSSID‌ها (اتحاد دو مجموعه)
    final allBssids = <String>{...observedMap.keys, ...fingerprintMap.keys};

    // محاسبه فاصله اقلیدسی
    double distance = 0.0;
    const defaultRssi = -100; // مقدار پیش‌فرض برای APهای مشاهده نشده

    for (final bssid in allBssids) {
      final obsRssi = observedMap[bssid]?.toDouble() ?? defaultRssi.toDouble();
      final fpRssi = fingerprintMap[bssid]?.toDouble() ?? defaultRssi.toDouble();
      
      final diff = obsRssi - fpRssi;
      distance += diff * diff;
    }

    // ریشه دوم فاصله اقلیدسی
    return math.sqrt(distance);
  }

  /// محاسبه ضریب اطمینان
  /// 
  /// اعتماد بر اساس:
  /// - میانگین فاصله تا همسایه‌ها (هرچه کمتر، اعتماد بیشتر)
  /// - یکنواختی فاصله‌ها (هرچه یکنواخت‌تر، اعتماد بیشتر)
  double _calculateConfidence(double avgDistance, List<double> distances) {
    if (distances.isEmpty) return 0.0;

    // نرمال‌سازی بر اساس فاصله
    // فاصله 0 = اعتماد 1.0
    // فاصله بزرگ = اعتماد نزدیک به 0
    final normalizedDistance = 1.0 / (1.0 + avgDistance / 100.0); // تقسیم بر 100 برای نرمال‌سازی

    // محاسبه انحراف معیار برای بررسی یکنواختی
    if (distances.length > 1) {
      final mean = avgDistance;
      final variance = distances.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) / distances.length;
      final stdDev = math.sqrt(variance);
      
      // هرچه انحراف معیار کمتر باشد، اعتماد بیشتر است
      final consistency = 1.0 / (1.0 + stdDev / 50.0);
      
      // ترکیب نرمال‌سازی فاصله و یکنواختی
      return (normalizedDistance * 0.7 + consistency * 0.3).clamp(0.0, 1.0);
    }

    return normalizedDistance.clamp(0.0, 1.0);
  }

  /// تعیین لیبل ناحیه بر اساس اکثریت همسایه‌ها
  String? _determineZoneLabel(List<FingerprintEntry> neighbors) {
    if (neighbors.isEmpty) return null;

    final labelCounts = <String, int>{};
    for (final neighbor in neighbors) {
      if (neighbor.zoneLabel != null && neighbor.zoneLabel!.isNotEmpty) {
        labelCounts[neighbor.zoneLabel!] = (labelCounts[neighbor.zoneLabel!] ?? 0) + 1;
      }
    }

    if (labelCounts.isEmpty) return null;

    // پیدا کردن لیبل با بیشترین تعداد
    String? mostCommonLabel;
    int maxCount = 0;
    labelCounts.forEach((label, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommonLabel = label;
      }
    });

    // اگر اکثریت (بیش از 50%) یک لیبل داشته باشند، آن را برمی‌گردانیم
    if (maxCount > neighbors.length / 2) {
      return mostCommonLabel;
    }

    return null;
  }

  /// محاسبه فاصله ساده (بدون ریشه) - برای بهینه‌سازی
  /// در صورت نیاز می‌توان از این استفاده کرد
  double _calculateDistanceSquared(List<WifiReading> observed, List<WifiReading> fingerprint) {
    final observedMap = <String, int>{};
    for (final ap in observed) {
      observedMap[ap.bssid] = ap.rssi;
    }

    final fingerprintMap = <String, int>{};
    for (final ap in fingerprint) {
      fingerprintMap[ap.bssid] = ap.rssi;
    }

    final allBssids = <String>{...observedMap.keys, ...fingerprintMap.keys};
    double distanceSquared = 0.0;
    const defaultRssi = -100;

    for (final bssid in allBssids) {
      final obsRssi = observedMap[bssid]?.toDouble() ?? defaultRssi.toDouble();
      final fpRssi = fingerprintMap[bssid]?.toDouble() ?? defaultRssi.toDouble();
      
      final diff = obsRssi - fpRssi;
      distanceSquared += diff * diff;
    }

    return distanceSquared;
  }
}










