import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'data_model.dart';
import 'config.dart';
import 'local_database.dart';
import 'services/prediction_service.dart';
import 'utils/rssi_filter.dart';

/// پیاده‌سازی الگوریتم KNN برای تخمین موقعیت (Hybrid: Wi-Fi + Cell)
class KnnLocalization {
  final LocalDatabase _database;

  KnnLocalization(this._database);

  /// تخمین موقعیت Hybrid (Wi-Fi + Cell)
  /// 
  /// این متد به صورت خودکار تصمیم می‌گیرد که از Wi-Fi، Cell یا هر دو استفاده کند:
  /// - اگر Wi-Fi قوی باشد (>= 3 AP با RSSI > -80): اولویت با Wi-Fi
  /// - اگر Wi-Fi ضعیف یا موجود نباشد: از Cell استفاده می‌کند
  /// - در صورت امکان، از هر دو استفاده می‌کند (Hybrid)
  Future<LocationEstimate?> estimateLocationHybrid({
    WifiScanResult? wifiScan,
    CellScanResult? cellScan,
    int k = AppConfig.defaultK,
  }) async {
    // بررسی قدرت سیگنال Wi-Fi
    final wifiStrength = _calculateWifiStrength(wifiScan);
    final hasStrongWifi = wifiStrength >= 0.5; // حداقل 3 AP با RSSI > -80
    final hasWifi = wifiScan != null && wifiScan.accessPoints.isNotEmpty;
    final hasCell = cellScan != null && 
                    (cellScan.servingCell != null || cellScan.neighboringCells.isNotEmpty);

    // تصمیم‌گیری استراتژی
    if (hasStrongWifi && hasWifi) {
      // اولویت با Wi-Fi
      debugPrint('Using Wi-Fi priority mode');
      return await estimateLocation(wifiScan!, k: k);
    } else if (hasWifi && hasCell) {
      // استفاده از هر دو (Hybrid)
      debugPrint('Using Hybrid mode (Wi-Fi + Cell)');
      return await _estimateLocationHybrid(wifiScan!, cellScan!, k: k);
    } else if (hasCell) {
      // فقط Cell
      debugPrint('Using Cell-only mode');
      return await estimateLocationFromCell(cellScan!, k: k);
    } else if (hasWifi) {
      // فقط Wi-Fi (حتی اگر ضعیف باشد)
      debugPrint('Using Wi-Fi-only mode (weak signal)');
      return await estimateLocation(wifiScan!, k: k);
    }

    // هیچ سیگنالی در دسترس نیست
    debugPrint('No signals available for localization');
    return null;
  }

  /// محاسبه قدرت نسبی سیگنال Wi-Fi (0.0 تا 1.0)
  double _calculateWifiStrength(WifiScanResult? wifiScan) {
    if (wifiScan == null || wifiScan.accessPoints.isEmpty) return 0.0;
    
    final strongApCount = wifiScan.accessPoints
        .where((ap) => ap.rssi > AppConfig.fairRssi) // RSSI > -70
        .length;
    
    if (wifiScan.accessPoints.length < AppConfig.minApCountForEvaluation) {
      return 0.0;
    }
    
    // نرمال‌سازی بر اساس تعداد AP و قدرت سیگنال
    final avgRssi = wifiScan.accessPoints
        .map((ap) => ap.rssi.toDouble())
        .reduce((a, b) => a + b) / wifiScan.accessPoints.length;
    
    // تبدیل RSSI به امتیاز (0.0 تا 1.0)
    // RSSI -50 = 1.0, RSSI -100 = 0.0
    final rssiScore = ((avgRssi + 100) / 50).clamp(0.0, 1.0);
    
    // ترکیب تعداد AP و قدرت سیگنال
    final apScore = (strongApCount / AppConfig.minApCountForEvaluation).clamp(0.0, 1.0);
    
    return (rssiScore * 0.6 + apScore * 0.4);
  }

  /// تخمین موقعیت Hybrid (ترکیب Wi-Fi و Cell)
  Future<LocationEstimate?> _estimateLocationHybrid(
    WifiScanResult wifiScan,
    CellScanResult cellScan, {
    int k = AppConfig.defaultK,
  }) async {
    // دریافت اثرانگشت‌های Wi-Fi و Cell
    final wifiFingerprints = await _database.getAllFingerprints();
    final cellFingerprints = await _database.getAllCellFingerprints();
    
    if (wifiFingerprints.isEmpty && cellFingerprints.isEmpty) {
      return null;
    }

    // محاسبه فاصله‌ها برای Wi-Fi
    final wifiDistances = <DistanceRecord>[];
    for (int i = 0; i < wifiFingerprints.length; i++) {
      final distance = _calculateDistance(wifiScan.accessPoints, wifiFingerprints[i].accessPoints);
      wifiDistances.add(DistanceRecord(
        distance: distance,
        fingerprint: wifiFingerprints[i],
        index: i,
      ));
    }

    // محاسبه فاصله‌ها برای Cell
    final cellDistances = <_CellDistanceRecord>[];
    final allCells = cellScan.allCells;
    for (int i = 0; i < cellFingerprints.length; i++) {
      final distance = _calculateCellDistance(allCells, cellFingerprints[i].cellTowers);
      cellDistances.add(_CellDistanceRecord(
        distance: distance,
        fingerprint: cellFingerprints[i],
        index: i,
      ));
    }

    // ترکیب نتایج Wi-Fi و Cell
    final combinedNeighbors = <_CombinedNeighbor>[];
    
    // تبدیل Wi-Fi fingerprints به combined format
    for (final wifiDist in wifiDistances) {
      combinedNeighbors.add(_CombinedNeighbor(
        latitude: wifiDist.fingerprint.latitude,
        longitude: wifiDist.fingerprint.longitude,
        wifiDistance: wifiDist.distance,
        cellDistance: null,
        zoneLabel: wifiDist.fingerprint.zoneLabel,
      ));
    }

    // تبدیل Cell fingerprints به combined format
    for (final cellDist in cellDistances) {
      // بررسی اینکه آیا این موقعیت قبلاً اضافه شده (از Wi-Fi)
      final existing = combinedNeighbors.firstWhere(
        (n) => (n.latitude - cellDist.fingerprint.latitude).abs() < 0.0001 &&
               (n.longitude - cellDist.fingerprint.longitude).abs() < 0.0001,
        orElse: () => _CombinedNeighbor(
          latitude: cellDist.fingerprint.latitude,
          longitude: cellDist.fingerprint.longitude,
          wifiDistance: null,
          cellDistance: cellDist.distance,
          zoneLabel: cellDist.fingerprint.zoneLabel,
        ),
      );
      
      if (existing.cellDistance == null) {
        existing.cellDistance = cellDist.distance;
      } else {
        // اگر موقعیت جدید است، اضافه کن
        if (existing.latitude != cellDist.fingerprint.latitude ||
            existing.longitude != cellDist.fingerprint.longitude) {
          combinedNeighbors.add(_CombinedNeighbor(
            latitude: cellDist.fingerprint.latitude,
            longitude: cellDist.fingerprint.longitude,
            wifiDistance: null,
            cellDistance: cellDist.distance,
            zoneLabel: cellDist.fingerprint.zoneLabel,
          ));
        }
      }
    }

    // محاسبه فاصله ترکیبی برای هر همسایه
    for (final neighbor in combinedNeighbors) {
      neighbor.combinedDistance = _calculateCombinedDistance(
        neighbor.wifiDistance,
        neighbor.cellDistance,
      );
    }

    // مرتب‌سازی بر اساس فاصله ترکیبی
    combinedNeighbors.sort((a, b) {
      final aDist = a.combinedDistance ?? double.infinity;
      final bDist = b.combinedDistance ?? double.infinity;
      return aDist.compareTo(bDist);
    });

    // انتخاب k همسایه نزدیک
    final kNearest = k < combinedNeighbors.length ? k : combinedNeighbors.length;
    if (kNearest == 0) return null;

    final nearestNeighbors = combinedNeighbors.take(kNearest).toList();

    // محاسبه موقعیت تخمینی با میانگین وزن‌دار
    double latSum = 0.0;
    double lonSum = 0.0;
    double weightSum = 0.0;
    final distances = <double>[];

    for (final neighbor in nearestNeighbors) {
      final distance = neighbor.combinedDistance ?? double.infinity;
      if (distance == double.infinity) continue;
      
      final weight = 1.0 / (distance + 1.0);
      latSum += neighbor.latitude * weight;
      lonSum += neighbor.longitude * weight;
      weightSum += weight;
      distances.add(distance);
    }

    if (weightSum == 0) return null;

    final estimatedLat = latSum / weightSum;
    final estimatedLon = lonSum / weightSum;
    final avgDistance = distances.reduce((a, b) => a + b) / distances.length;
    final confidence = _calculateConfidence(avgDistance, distances);

    // تعیین لیبل ناحیه
    final zoneLabel = _determineZoneLabelFromCombined(nearestNeighbors);

    // ساخت لیست همسایه‌ها برای LocationEstimate (تبدیل به FingerprintEntry)
    final neighborFingerprints = nearestNeighbors.map((n) {
      return FingerprintEntry(
        fingerprintId: 'hybrid_${n.latitude}_${n.longitude}',
        latitude: n.latitude,
        longitude: n.longitude,
        zoneLabel: n.zoneLabel,
        accessPoints: [], // در حالت Hybrid، accessPoints خالی است
        createdAt: DateTime.now(),
      );
    }).toList();

    return LocationEstimate(
      latitude: estimatedLat,
      longitude: estimatedLon,
      confidence: confidence,
      zoneLabel: zoneLabel,
      nearestNeighbors: neighborFingerprints,
      averageDistance: avgDistance,
    );
  }

  /// محاسبه فاصله ترکیبی از Wi-Fi و Cell
  double _calculateCombinedDistance(double? wifiDistance, double? cellDistance) {
    if (wifiDistance != null && cellDistance != null) {
      // ترکیب وزن‌دار: Wi-Fi 60%, Cell 40%
      return wifiDistance * 0.6 + cellDistance * 0.4;
    } else if (wifiDistance != null) {
      return wifiDistance;
    } else if (cellDistance != null) {
      return cellDistance;
    }
    return double.infinity;
  }

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
      // ممکن است یک outage (قطع سیگنال) باشد؛ سعی می‌کنیم از PredictionService استفاده کنیم
      try {
        final deviceId = scanResult.deviceId ?? '';
        final predictionService = PredictionService(_database);
        final preds = await predictionService.predictDuringOutage(deviceId: deviceId, steps: 1);
        if (preds.isNotEmpty) {
          // بازگرداندن اولین پیش‌بینی با نشانه‌ای از پیش‌بینی (confidence ممکن است پایین باشد)
          return preds.first;
        }
      } catch (e) {
        // اگر پیش‌بینی شکست خورد، به رفتار قبلی برمی‌گردیم (null)
      }

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

    // انتخاب k همسایه نزدیک (با Adaptive K)
    int effectiveK = k;
    if (AppConfig.enableAdaptiveK) {
      effectiveK = _resolveAdaptiveK(distances, k);
    }
    final kNearest = effectiveK < distances.length ? effectiveK : distances.length;
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

  /// محاسبه فاصله بین دو بردار Wi-Fi با وزن‌دهی RSSI
  /// 
  /// از فاصله اقلیدسی وزن‌دار استفاده می‌کند:
  /// - برای هر BSSID مشترک: (RSSI1 - RSSI2)² * weight
  /// - وزن بر اساس قدرت RSSI محاسبه می‌شود
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

    // محاسبه فاصله اقلیدسی وزن‌دار
    double distance = 0.0;
    const defaultRssi = -100; // مقدار پیش‌فرض برای APهای مشاهده نشده

    for (final bssid in allBssids) {
      final obsRssi = observedMap[bssid]?.toDouble() ?? defaultRssi.toDouble();
      final fpRssi = fingerprintMap[bssid]?.toDouble() ?? defaultRssi.toDouble();
      
      final diff = obsRssi - fpRssi;
      
      // وزن‌دهی RSSI (اگر فعال باشد)
      if (AppConfig.useRssiWeighting) {
        // استفاده از میانگین RSSI برای محاسبه وزن
        final avgRssi = ((obsRssi + fpRssi) / 2).round();
        final weight = RssiFilter.calculateRssiWeight(avgRssi);
        distance += diff * diff * weight;
      } else {
        distance += diff * diff;
      }
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

  int _resolveAdaptiveK(List<DistanceRecord> distances, int baseK) {
    final safeBase = baseK.clamp(AppConfig.minK, AppConfig.maxK);
    if (!AppConfig.enableAdaptiveK || distances.isEmpty) {
      return safeBase;
    }

    final seed = distances.take(safeBase).toList();
    if (seed.isEmpty) {
      return safeBase;
    }

    final centerLat = seed.fold<double>(0, (sum, d) => sum + d.fingerprint.latitude) / seed.length;
    final centerLon = seed.fold<double>(0, (sum, d) => sum + d.fingerprint.longitude) / seed.length;
    final radiusDeg = AppConfig.adaptiveRadiusMeters / 111320.0;

    int densityCount = 0;
    for (final record in distances) {
      final latDiff = (record.fingerprint.latitude - centerLat).abs();
      final lonDiff = (record.fingerprint.longitude - centerLon).abs();
      if (latDiff <= radiusDeg && lonDiff <= radiusDeg) {
        densityCount++;
      }
    }

    if (densityCount == 0) {
      return safeBase;
    }

    final adaptiveK = (densityCount / AppConfig.adaptiveNeighborsPerK).round();
    return adaptiveK.clamp(AppConfig.minK, AppConfig.maxK);
  }

  /// تخمین موقعیت بر اساس اسکن Cell
  Future<LocationEstimate?> estimateLocationFromCell(
    CellScanResult cellScan, {
    int k = AppConfig.defaultK,
  }) async {
    // بارگذاری اثرانگشت‌های سلولی
    final cellFingerprints = await _database.getAllCellFingerprints();
    
    if (cellFingerprints.isEmpty) {
      return null;
    }

    final allCells = cellScan.allCells;
    if (allCells.isEmpty) {
      return null;
    }

    // محاسبه فاصله‌ها
    final distances = <_CellDistanceRecord>[];
    
    for (int i = 0; i < cellFingerprints.length; i++) {
      final fingerprint = cellFingerprints[i];
      final distance = _calculateCellDistance(allCells, fingerprint.cellTowers);
      
      distances.add(_CellDistanceRecord(
        distance: distance,
        fingerprint: fingerprint,
        index: i,
      ));
    }

    // مرتب‌سازی بر اساس فاصله
    distances.sort((a, b) => a.distance.compareTo(b.distance));

    // انتخاب k همسایه نزدیک
    int effectiveK = k;
    if (AppConfig.enableAdaptiveK) {
      // استفاده از Adaptive K برای Cell (نیاز به تبدیل CellDistanceRecord به DistanceRecord)
      final wifiDistances = distances.map((d) => DistanceRecord(
        distance: d.distance,
        fingerprint: FingerprintEntry(
          fingerprintId: d.fingerprint.fingerprintId,
          latitude: d.fingerprint.latitude,
          longitude: d.fingerprint.longitude,
          zoneLabel: d.fingerprint.zoneLabel,
          accessPoints: [],
          createdAt: d.fingerprint.createdAt,
        ),
        index: d.index,
      )).toList();
      effectiveK = _resolveAdaptiveK(wifiDistances, k);
    }
    
    final kNearest = effectiveK < distances.length ? effectiveK : distances.length;
    if (kNearest == 0) {
      return null;
    }

    final nearestNeighbors = distances.take(kNearest).toList();
    final nearestDistances = nearestNeighbors.map((d) => d.distance).toList();

    // محاسبه موقعیت تخمینی با میانگین وزن‌دار
    double latSum = 0.0;
    double lonSum = 0.0;
    double weightSum = 0.0;

    for (int i = 0; i < nearestNeighbors.length; i++) {
      final neighbor = nearestNeighbors[i];
      final distance = nearestDistances[i];
      final weight = 1.0 / (distance + 1.0);

      latSum += neighbor.fingerprint.latitude * weight;
      lonSum += neighbor.fingerprint.longitude * weight;
      weightSum += weight;
    }

    if (weightSum == 0) {
      return null;
    }

    final estimatedLat = latSum / weightSum;
    final estimatedLon = lonSum / weightSum;
    final avgDistance = nearestDistances.reduce((a, b) => a + b) / nearestDistances.length;
    final confidence = _calculateConfidence(avgDistance, nearestDistances);

    // تعیین لیبل ناحیه
    final zoneLabel = _determineCellZoneLabel(nearestNeighbors.map((d) => d.fingerprint).toList());

    // تبدیل به FingerprintEntry برای LocationEstimate
    final neighborFingerprints = nearestNeighbors.map((d) {
      return FingerprintEntry(
        fingerprintId: d.fingerprint.fingerprintId,
        latitude: d.fingerprint.latitude,
        longitude: d.fingerprint.longitude,
        zoneLabel: d.fingerprint.zoneLabel,
        accessPoints: [],
        createdAt: d.fingerprint.createdAt,
      );
    }).toList();

    return LocationEstimate(
      latitude: estimatedLat,
      longitude: estimatedLon,
      confidence: confidence,
      zoneLabel: zoneLabel,
      nearestNeighbors: neighborFingerprints,
      averageDistance: avgDistance,
    );
  }

  /// محاسبه فاصله بین دو بردار Cell Tower
  double _calculateCellDistance(List<CellTowerInfo> observed, List<CellTowerInfo> fingerprint) {
    // ساخت Map برای دسترسی سریع‌تر (بر اساس uniqueId)
    final observedMap = <String, CellTowerInfo>{};
    for (final cell in observed) {
      final key = cell.uniqueId;
      if (key.isNotEmpty) {
        observedMap[key] = cell;
      }
    }

    final fingerprintMap = <String, CellTowerInfo>{};
    for (final cell in fingerprint) {
      final key = cell.uniqueId;
      if (key.isNotEmpty) {
        fingerprintMap[key] = cell;
      }
    }

    // جمع‌آوری تمام Cell IDs
    final allCellIds = <String>{...observedMap.keys, ...fingerprintMap.keys};

    // محاسبه فاصله اقلیدسی وزن‌دار
    double distance = 0.0;
    const defaultSignal = -120; // مقدار پیش‌فرض برای دکل‌های مشاهده نشده

    for (final cellId in allCellIds) {
      final obsCell = observedMap[cellId];
      final fpCell = fingerprintMap[cellId];
      
      final obsSignal = obsCell?.signalStrength?.toDouble() ?? defaultSignal.toDouble();
      final fpSignal = fpCell?.signalStrength?.toDouble() ?? defaultSignal.toDouble();
      
      final diff = obsSignal - fpSignal;
      
      // وزن‌دهی بر اساس قدرت سیگنال
      final avgSignal = (obsSignal + fpSignal) / 2;
      final weight = _calculateCellWeight(avgSignal);
      
      distance += diff * diff * weight;
    }

    // اگر هیچ دکل مشترکی وجود نداشت، فاصله بزرگ برمی‌گردانیم
    if (allCellIds.isEmpty) {
      return 1000.0; // فاصله بزرگ
    }

    return math.sqrt(distance);
  }

  /// محاسبه وزن برای دکل بر اساس قدرت سیگنال
  double _calculateCellWeight(double signalStrength) {
    // سیگنال قوی‌تر = وزن بیشتر
    // -50 dBm = وزن 1.0, -120 dBm = وزن 0.1
    final normalized = ((signalStrength + 120) / 70).clamp(0.0, 1.0);
    return 0.1 + normalized * 0.9;
  }

  /// تعیین لیبل ناحیه برای Cell fingerprints
  String? _determineCellZoneLabel(List<CellFingerprintEntry> neighbors) {
    if (neighbors.isEmpty) return null;

    final labelCounts = <String, int>{};
    for (final neighbor in neighbors) {
      if (neighbor.zoneLabel != null && neighbor.zoneLabel!.isNotEmpty) {
        labelCounts[neighbor.zoneLabel!] = (labelCounts[neighbor.zoneLabel!] ?? 0) + 1;
      }
    }

    if (labelCounts.isEmpty) return null;

    String? mostCommonLabel;
    int maxCount = 0;
    labelCounts.forEach((label, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommonLabel = label;
      }
    });

    if (maxCount > neighbors.length / 2) {
      return mostCommonLabel;
    }

    return null;
  }

  /// تعیین لیبل ناحیه برای Combined neighbors
  String? _determineZoneLabelFromCombined(List<_CombinedNeighbor> neighbors) {
    if (neighbors.isEmpty) return null;

    final labelCounts = <String, int>{};
    for (final neighbor in neighbors) {
      if (neighbor.zoneLabel != null && neighbor.zoneLabel!.isNotEmpty) {
        labelCounts[neighbor.zoneLabel!] = (labelCounts[neighbor.zoneLabel!] ?? 0) + 1;
      }
    }

    if (labelCounts.isEmpty) return null;

    String? mostCommonLabel;
    int maxCount = 0;
    labelCounts.forEach((label, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommonLabel = label;
      }
    });

    if (maxCount > neighbors.length / 2) {
      return mostCommonLabel;
    }

    return null;
  }
}

/// رکورد فاصله برای Cell fingerprints
class _CellDistanceRecord {
  final double distance;
  final CellFingerprintEntry fingerprint;
  final int index;

  _CellDistanceRecord({
    required this.distance,
    required this.fingerprint,
    required this.index,
  });
}

/// همسایه ترکیبی (Hybrid) برای محاسبه فاصله ترکیبی
class _CombinedNeighbor {
  final double latitude;
  final double longitude;
  double? wifiDistance;
  double? cellDistance;
  double? combinedDistance;
  final String? zoneLabel;

  _CombinedNeighbor({
    required this.latitude,
    required this.longitude,
    this.wifiDistance,
    this.cellDistance,
    this.combinedDistance,
    this.zoneLabel,
  });
}










