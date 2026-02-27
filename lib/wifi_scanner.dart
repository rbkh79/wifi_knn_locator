import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'data_model.dart';
import 'config.dart';
import 'utils/privacy_utils.dart';

/// ماژول اسکن Wi-Fi
class WifiScanner {
  /// درخواست مجوزهای لازم
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final locationStatus = await Permission.location.request();
      if (!locationStatus.isGranted) {
        debugPrint('Location permission denied');
        return false;
      }
    }
    return true;
  }

  /// بررسی وضعیت مجوزها
  static Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      final locationStatus = await Permission.location.status;
      return locationStatus.isGranted;
    }
    return true;
  }

  /// اجرای اسکن Wi-Fi
  /// 
  /// این متد:
  /// 1. مجوزها را بررسی می‌کند (اما حتی بدون GPS هم کار می‌کند)
  /// 2. اسکن را شروع می‌کند
  /// 3. نتایج را جمع‌آوری می‌کند
  /// 4. WifiScanResult را برمی‌گرداند
  static Future<WifiScanResult> performScan() async {
    // بررسی مجوزها - اما حتی اگر Location Service خاموش باشد، سعی می‌کنیم
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      // درخواست مجوز - اما اگر رد شد، باز هم ادامه می‌دهیم
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('Location permission not granted, but continuing anyway...');
        // ادامه می‌دهیم - ممکن است در برخی دستگاه‌ها کار کند
      }
    }

    // دریافت شناسه دستگاه (هش‌شده)
    final deviceId = await PrivacyUtils.getDeviceId();

    // بررسی اینکه آیا می‌توانیم نتایج را دریافت کنیم
    try {
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) {
        debugPrint('Cannot get scanned results: $canGet');
        // باز هم سعی می‌کنیم - ممکن است کار کند
      }
    } catch (e) {
      debugPrint('Error checking canGetScannedResults: $e');
      // ادامه می‌دهیم
    }

    // شروع اسکن - حتی اگر Location Service خاموش باشد
    try {
      await WiFiScan.instance.startScan();
      debugPrint('WiFi scan started successfully');
    } catch (e) {
      debugPrint('startScan() error: $e');
      // ادامه می‌دهیم - ممکن است نتایج قبلی موجود باشد
    }

    // انتظار برای نتایج
    await Future.delayed(AppConfig.scanWaitTime);

    // دریافت نتایج - چند بار تلاش می‌کنیم
    List<dynamic>? results;
    int retryCount = 0;
    const maxRetries = 3;
    
    while (results == null && retryCount < maxRetries) {
      try {
        results = await WiFiScan.instance.getScannedResults();
        if (results != null && results.isNotEmpty) {
          debugPrint('Got ${results.length} WiFi networks');
          break;
        }
      } catch (e) {
        debugPrint('getScannedResults() attempt ${retryCount + 1} error: $e');
        if (retryCount < maxRetries - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      retryCount++;
    }

    // تبدیل نتایج به WifiReading
    final accessPoints = <WifiReading>[];

    if (results != null && results.isNotEmpty) {
      for (final network in results) {
        try {
          final dyn = network as dynamic;
          final String bssid = (dyn.bssid ?? dyn.bss?.toString() ?? '') as String;
          
          if (bssid.isEmpty) continue;

          final int rssi = (dyn.level ?? dyn.rssi ?? -100) as int;
          final int? frequency = dyn.frequency as int?;
          final String? ssid = dyn.ssid as String?;

          accessPoints.add(WifiReading(
            bssid: bssid,
            rssi: rssi,
            frequency: frequency,
            ssid: ssid,
          ));
        } catch (e) {
          debugPrint('Error parsing network: $e');
        }
      }
    }

    // اگر هیچ نتیجه‌ای پیدا نشد، پیام هشدار می‌دهیم اما خطا نمی‌دهیم
    if (accessPoints.isEmpty) {
      debugPrint('No WiFi networks found. This might be because:');
      debugPrint('1. Location permission is not granted');
      debugPrint('2. Location Service is disabled (but this should not prevent WiFi scan)');
      debugPrint('3. No WiFi networks are available');
      debugPrint('4. WiFi is disabled on the device');
    }

    // مرتب‌سازی بر اساس RSSI (قوی‌ترین اول)
    accessPoints.sort((a, b) => b.rssi.compareTo(a.rssi));

    debugPrint('WiFi scan completed: ${accessPoints.length} networks found');

    return WifiScanResult(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      accessPoints: accessPoints,
    );
  }

  /// اسکن شبیه‌سازی شده (برای تست)
  static Future<WifiScanResult> performSimulatedScan() async {
    final deviceId = await PrivacyUtils.getDeviceId();
    
    final accessPoints = [
      WifiReading(bssid: '00:1A:2B:3C:4D:5E', rssi: -45, frequency: 2412),
      WifiReading(bssid: '00:1A:2B:3C:4D:5F', rssi: -65, frequency: 2437),
      WifiReading(bssid: '00:1A:2B:3C:4D:60', rssi: -72, frequency: 2462),
    ];

    return WifiScanResult(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      accessPoints: accessPoints,
    );
  }

  /// بررسی اینکه آیا اسکن Wi-Fi در دسترس است
  static Future<bool> canGetScannedResults() async {
    try {
      final canGet = await WiFiScan.instance.canGetScannedResults();
      return canGet == CanGetScannedResults.yes;
    } catch (e) {
      debugPrint('canGetScannedResults() error: $e');
      return false;
    }
  }
}






