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
  /// 1. مجوزها را بررسی می‌کند
  /// 2. اسکن را شروع می‌کند
  /// 3. نتایج را جمع‌آوری می‌کند
  /// 4. WifiScanResult را برمی‌گرداند
  static Future<WifiScanResult> performScan() async {
    // بررسی مجوزها
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) {
        throw Exception('Location permission not granted');
      }
    }

    // دریافت شناسه دستگاه (هش‌شده)
    final deviceId = await PrivacyUtils.getDeviceId();

    // شروع اسکن
    try {
      await WiFiScan.instance.startScan();
    } catch (e) {
      debugPrint('startScan() error: $e');
      // ادامه می‌دهیم حتی اگر startScan خطا بدهد
    }

    // انتظار برای نتایج
    await Future.delayed(AppConfig.scanWaitTime);

    // دریافت نتایج
    List<dynamic>? results;
    try {
      results = await WiFiScan.instance.getScannedResults();
    } catch (e) {
      debugPrint('getScannedResults() error: $e');
      results = null;
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



