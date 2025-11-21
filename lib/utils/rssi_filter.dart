import 'dart:math' as math;
import '../data_model.dart';
import '../config.dart';

/// ابزارهای فیلتر و پردازش RSSI برای بهبود دقت
class RssiFilter {
  /// فیلتر نویز با میانگین متحرک
  /// چند اسکن را می‌گیرد و میانگین RSSI را برمی‌گرداند
  static List<WifiReading> applyMovingAverage(
    List<List<WifiReading>> scanHistory,
  ) {
    if (scanHistory.isEmpty) return [];

    // ساخت Map برای جمع‌آوری RSSIهای هر BSSID
    final bssidMap = <String, List<int>>{};

    for (final scan in scanHistory) {
      for (final reading in scan) {
        bssidMap.putIfAbsent(reading.bssid, () => []);
        bssidMap[reading.bssid]!.add(reading.rssi);
      }
    }

    // محاسبه میانگین برای هر BSSID
    final filtered = <WifiReading>[];
    bssidMap.forEach((bssid, rssiList) {
      if (rssiList.isEmpty) return;

      // استفاده از میانه برای مقاوم‌تر بودن در برابر outliers
      rssiList.sort();
      final medianRssi = rssiList.length.isOdd
          ? rssiList[rssiList.length ~/ 2]
          : (rssiList[rssiList.length ~/ 2 - 1] + rssiList[rssiList.length ~/ 2]) ~/ 2;

      // یا میانگین
      final avgRssi = (rssiList.reduce((a, b) => a + b) / rssiList.length).round();

      // استفاده از میانه (مقاوم‌تر در برابر نویز)
      filtered.add(WifiReading(
        bssid: bssid,
        rssi: medianRssi,
        frequency: null, // فرکانس را از اولین اسکن می‌توان گرفت
        ssid: null,
      ));
    });

    return filtered;
  }

  /// حذف APهای موقت (که در درصد کمی از اسکن‌ها ظاهر شده‌اند)
  static List<WifiReading> removeTemporaryAps(
    List<List<WifiReading>> scanHistory,
    int minOccurrencePercent,
  ) {
    if (scanHistory.isEmpty) return [];

    final totalScans = scanHistory.length;
    final minOccurrences = (totalScans * minOccurrencePercent / 100).ceil();

    // شمارش تعداد تکرار هر BSSID
    final bssidCounts = <String, int>{};
    final bssidRssiMap = <String, List<int>>{};

    for (final scan in scanHistory) {
      final seenInThisScan = <String>{};
      for (final reading in scan) {
        if (!seenInThisScan.contains(reading.bssid)) {
          bssidCounts[reading.bssid] = (bssidCounts[reading.bssid] ?? 0) + 1;
          seenInThisScan.add(reading.bssid);
        }
        bssidRssiMap.putIfAbsent(reading.bssid, () => []);
        bssidRssiMap[reading.bssid]!.add(reading.rssi);
      }
    }

    // فقط APهایی که در حداقل درصد اسکن‌ها ظاهر شده‌اند
    final filtered = <WifiReading>[];
    bssidCounts.forEach((bssid, count) {
      if (count >= minOccurrences) {
        // محاسبه میانگین RSSI برای این AP
        final rssiList = bssidRssiMap[bssid]!;
        rssiList.sort();
        final medianRssi = rssiList.length.isOdd
            ? rssiList[rssiList.length ~/ 2]
            : (rssiList[rssiList.length ~/ 2 - 1] + rssiList[rssiList.length ~/ 2]) ~/ 2;

        filtered.add(WifiReading(
          bssid: bssid,
          rssi: medianRssi,
          frequency: null,
          ssid: null,
        ));
      }
    });

    return filtered;
  }

  /// محاسبه وزن RSSI برای KNN
  /// RSSI قوی‌تر = وزن بیشتر
  static double calculateRssiWeight(int rssi) {
    // تبدیل RSSI به قدرت (mW) و سپس وزن
    // وزن = 10^(-RSSI/10) یا 1 / (RSSI²)
    if (rssi >= 0) return 0.0; // RSSI منفی است
    
    // روش 1: استفاده از توان RSSI
    final powerWeight = math.pow(10, rssi / 10.0).abs();
    
    // روش 2: استفاده از معکوس مربع RSSI (ساده‌تر)
    final rssiSquaredWeight = 1.0 / (rssi * rssi).abs();
    
    // ترکیب هر دو روش
    return (powerWeight * 0.7 + rssiSquaredWeight * 0.3);
  }

  /// محاسبه واریانس RSSI برای validation
  static double calculateRssiVariance(List<int> rssiValues) {
    if (rssiValues.isEmpty) return 0.0;
    if (rssiValues.length == 1) return 0.0;

    final mean = rssiValues.reduce((a, b) => a + b) / rssiValues.length;
    final variance = rssiValues
        .map((r) => math.pow(r - mean, 2))
        .reduce((a, b) => a + b) / rssiValues.length;

    return variance;
  }

  /// بررسی همگرایی RSSI (برای validation)
  static bool isRssiConvergent(List<int> rssiValues, double maxVariance) {
    if (rssiValues.length < 2) return true;
    
    final variance = calculateRssiVariance(rssiValues);
    return variance <= maxVariance;
  }
}



