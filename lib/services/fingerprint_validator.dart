import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../config.dart';
import '../wifi_scanner.dart';
import '../utils/rssi_filter.dart';

/// سرویس اعتبارسنجی اثرانگشت‌ها برای جلوگیری از داده‌های بد
class FingerprintValidator {
  /// اعتبارسنجی اثرانگشت با انجام چند اسکن و بررسی همگرایی
  static Future<ValidationResult> validateFingerprint({
    required double latitude,
    required double longitude,
    int scanCount = AppConfig.validationScanCount,
  }) async {
    final scanHistory = <List<WifiReading>>[];

    // انجام چند اسکن
    for (int i = 0; i < scanCount; i++) {
      try {
        final scanResult = await WifiScanner.performScan();
        scanHistory.add(scanResult.accessPoints);
        
        // کمی صبر بین اسکن‌ها
        if (i < scanCount - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        debugPrint('Validation scan $i failed: $e');
      }
    }

    if (scanHistory.isEmpty) {
      return ValidationResult(
        isValid: false,
        reason: 'هیچ اسکنی انجام نشد',
        filteredAccessPoints: [],
      );
    }

    // بررسی همگرایی RSSI برای هر AP
    final bssidRssiMap = <String, List<int>>{};
    for (final scan in scanHistory) {
      for (final reading in scan) {
        bssidRssiMap.putIfAbsent(reading.bssid, () => []);
        bssidRssiMap[reading.bssid]!.add(reading.rssi);
      }
    }

    // فیلتر APهایی که همگرا نیستند
    final validAps = <WifiReading>[];
    final invalidAps = <String>[];

    bssidRssiMap.forEach((bssid, rssiList) {
      if (rssiList.length < 2) {
        // اگر فقط یک بار دیده شده، معتبر نیست
        invalidAps.add(bssid);
        return;
      }

      final isConvergent = RssiFilter.isRssiConvergent(
        rssiList,
        AppConfig.maxRssiVariance,
      );

      if (isConvergent) {
        // محاسبه میانه RSSI
        rssiList.sort();
        final medianRssi = rssiList.length.isOdd
            ? rssiList[rssiList.length ~/ 2]
            : (rssiList[rssiList.length ~/ 2 - 1] + rssiList[rssiList.length ~/ 2]) ~/ 2;

        validAps.add(WifiReading(
          bssid: bssid,
          rssi: medianRssi,
          frequency: null,
          ssid: null,
        ));
      } else {
        invalidAps.add(bssid);
      }
    });

    // حذف APهای موقت
    final filteredAps = AppConfig.useNoiseFiltering
        ? RssiFilter.removeTemporaryAps(
            scanHistory,
            AppConfig.minApOccurrencePercent,
          )
        : validAps;

    // بررسی حداقل تعداد AP
    if (filteredAps.length < AppConfig.minApCountForEvaluation) {
      return ValidationResult(
        isValid: false,
        reason: 'تعداد APهای معتبر کافی نیست (${filteredAps.length} < ${AppConfig.minApCountForEvaluation})',
        filteredAccessPoints: filteredAps,
        invalidAps: invalidAps,
      );
    }

    return ValidationResult(
      isValid: true,
      reason: 'اعتبارسنجی موفق',
      filteredAccessPoints: filteredAps,
      invalidAps: invalidAps,
    );
  }

  /// بررسی اینکه آیا دو اثرانگشت در فاصله کم ولی با RSSI خیلی متفاوت هستند
  static bool checkAnomaly(
    FingerprintEntry fp1,
    FingerprintEntry fp2,
    double maxDistanceMeters,
    double maxRssiDifference,
  ) {
    // محاسبه فاصله جغرافیایی
    final distance = _calculateGeographicDistance(
      fp1.latitude,
      fp1.longitude,
      fp2.latitude,
      fp2.longitude,
    );

    if (distance > maxDistanceMeters) {
      return false; // خیلی دور هستند، طبیعی است که RSSI متفاوت باشد
    }

    // مقایسه RSSI برای APهای مشترک
    final fp1Map = <String, int>{};
    for (final ap in fp1.accessPoints) {
      fp1Map[ap.bssid] = ap.rssi;
    }

    final fp2Map = <String, int>{};
    for (final ap in fp2.accessPoints) {
      fp2Map[ap.bssid] = ap.rssi;
    }

    final commonBssids = fp1Map.keys.where((b) => fp2Map.containsKey(b)).toList();
    
    if (commonBssids.isEmpty) {
      return false; // هیچ AP مشترکی ندارند
    }

    // بررسی تفاوت RSSI
    for (final bssid in commonBssids) {
      final diff = (fp1Map[bssid]! - fp2Map[bssid]!).abs();
      if (diff > maxRssiDifference) {
        return true; // تفاوت زیاد = anomaly
      }
    }

    return false;
  }

  /// محاسبه فاصله جغرافیایی به متر (Haversine formula)
  static double _calculateGeographicDistance(
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
}

/// نتیجه اعتبارسنجی
class ValidationResult {
  final bool isValid;
  final String reason;
  final List<WifiReading> filteredAccessPoints;
  final List<String>? invalidAps;

  ValidationResult({
    required this.isValid,
    required this.reason,
    required this.filteredAccessPoints,
    this.invalidAps,
  });
}

import 'dart:math' as math;

