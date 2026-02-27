/// سرویس مکان‌یابی داخلی (Indoor Localization Service)
/// 
/// این سرویس برای مکان‌یابی در محیط‌های بسته (Indoor) طراحی شده است
/// و به صورت کاملاً GPS-Free عمل می‌کند.
/// 
/// روش کار:
/// - از Wi-Fi Fingerprinting استفاده می‌کند
/// - الگوریتم KNN برای تخمین موقعیت به کار می‌رود
/// - پایگاه داده آفلاین SQLite برای ذخیره اثرانگشت‌ها
/// 
/// چرا GPS-Free؟
/// - در محیط‌های بسته، GPS دقت پایینی دارد یا اصلاً کار نمی‌کند
/// - Wi-Fi Fingerprinting دقت بهتری در محیط‌های Indoor ارائه می‌دهد
/// - نیازی به دسترسی به سرویس‌های خارجی نیست (حریم خصوصی بهتر)
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../knn_localization.dart';
import '../wifi_scanner.dart';

/// نتیجه مکان‌یابی داخلی
class IndoorLocalizationResult {
  final LocationEstimate? estimate;
  final bool isIndoor;
  final double wifiStrength; // قدرت نسبی سیگنال Wi-Fi (0.0 تا 1.0)
  final int accessPointCount;

  IndoorLocalizationResult({
    this.estimate,
    required this.isIndoor,
    required this.wifiStrength,
    required this.accessPointCount,
  });

  /// بررسی اینکه آیا نتیجه قابل اعتماد است
  bool get isReliable => 
      estimate != null && 
      estimate!.confidence >= 0.3 && 
      accessPointCount >= 3;
}

/// سرویس مکان‌یابی داخلی
class IndoorLocalizationService {
  final LocalDatabase _database;
  final KnnLocalization _knnLocalization;

  IndoorLocalizationService(this._database)
      : _knnLocalization = KnnLocalization(_database);

  /// انجام مکان‌یابی داخلی بر اساس اسکن Wi-Fi
  /// 
  /// این متد:
  /// 1. اسکن Wi-Fi را انجام می‌دهد
  /// 2. قدرت سیگنال Wi-Fi را ارزیابی می‌کند
  /// 3. با استفاده از KNN موقعیت را تخمین می‌زند
  /// 4. نتیجه را با ضریب اطمینان برمی‌گرداند
  /// 
  /// [k]: تعداد همسایه‌های نزدیک برای الگوریتم KNN (پیش‌فرض: 3)
  /// 
  /// Returns: IndoorLocalizationResult شامل تخمین موقعیت و اطلاعات محیط
  Future<IndoorLocalizationResult> performIndoorLocalization({
    int k = 3,
  }) async {
    try {
      // انجام اسکن Wi-Fi
      final wifiScan = await WifiScanner.performScan();

      // محاسبه قدرت نسبی سیگنال Wi-Fi
      final wifiStrength = _calculateWifiStrength(wifiScan);
      final accessPointCount = wifiScan.accessPoints.length;

      // بررسی اینکه آیا محیط Indoor است یا نه
      // معیار: حداقل 3 نقطه دسترسی با قدرت مناسب
      final isIndoor = accessPointCount >= 3 && wifiStrength > 0.3;

      if (!isIndoor || wifiScan.accessPoints.isEmpty) {
        debugPrint('Indoor localization: Not enough WiFi signals for indoor localization');
        return IndoorLocalizationResult(
          isIndoor: false,
          wifiStrength: wifiStrength,
          accessPointCount: accessPointCount,
        );
      }

      // تخمین موقعیت با استفاده از KNN
      final estimate = await _knnLocalization.estimateLocation(
        wifiScan,
        k: k,
      );

      debugPrint(
        'Indoor localization completed: '
        'APs=${accessPointCount}, '
        'Strength=${wifiStrength.toStringAsFixed(2)}, '
        'Confidence=${estimate?.confidence.toStringAsFixed(2) ?? "N/A"}',
      );

      return IndoorLocalizationResult(
        estimate: estimate,
        isIndoor: true,
        wifiStrength: wifiStrength,
        accessPointCount: accessPointCount,
      );
    } catch (e) {
      debugPrint('Error in indoor localization: $e');
      return IndoorLocalizationResult(
        isIndoor: false,
        wifiStrength: 0.0,
        accessPointCount: 0,
      );
    }
  }

  /// محاسبه قدرت نسبی سیگنال Wi-Fi
  /// 
  /// این متد بر اساس:
  /// - تعداد نقاط دسترسی (Access Points)
  /// - میانگین قدرت سیگنال (RSSI)
  /// 
  /// یک مقدار بین 0.0 تا 1.0 برمی‌گرداند که نشان‌دهنده قدرت نسبی است.
  double _calculateWifiStrength(WifiScanResult wifiScan) {
    if (wifiScan.accessPoints.isEmpty) return 0.0;

    // محاسبه میانگین RSSI
    final avgRssi = wifiScan.accessPoints
        .map((ap) => ap.rssi.toDouble())
        .reduce((a, b) => a + b) /
        wifiScan.accessPoints.length;

    // تبدیل RSSI به امتیاز (0.0 تا 1.0)
    // RSSI -50 dBm = 1.0 (عالی)
    // RSSI -100 dBm = 0.0 (ضعیف)
    final rssiScore = ((avgRssi + 100) / 50).clamp(0.0, 1.0);

    // امتیاز بر اساس تعداد AP
    // 3+ AP = 1.0, 1-2 AP = 0.5, 0 AP = 0.0
    final apCountScore = (wifiScan.accessPoints.length / 3.0).clamp(0.0, 1.0);

    // ترکیب امتیازها (60% RSSI, 40% تعداد AP)
    return (rssiScore * 0.6 + apCountScore * 0.4);
  }

  /// بررسی اینکه آیا محیط Indoor است یا نه
  /// 
  /// این متد بر اساس قدرت و تعداد سیگنال‌های Wi-Fi تصمیم می‌گیرد
  /// که آیا کاربر در محیط بسته (Indoor) است یا نه.
  Future<bool> isIndoorEnvironment() async {
    try {
      final wifiScan = await WifiScanner.performScan();
      final strength = _calculateWifiStrength(wifiScan);
      return wifiScan.accessPoints.length >= 3 && strength > 0.3;
    } catch (e) {
      debugPrint('Error checking indoor environment: $e');
      return false;
    }
  }
}

