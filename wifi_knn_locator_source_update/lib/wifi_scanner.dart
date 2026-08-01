import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import 'config.dart';
import 'data_model.dart';
import 'utils/privacy_utils.dart';

/// Wi-Fi scanning module with permission-safe behavior.
class WifiScanner {
  /// Location remains required for Android Wi-Fi scan results on many devices.
  /// Android 13+ nearby-Wi-Fi permission is requested opportunistically; denial
  /// does not crash the app and the scanner will still try the platform API.
  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      debugPrint('Location permission denied for Wi-Fi scanning');
      return false;
    }

    try {
      final nearbyStatus = await Permission.nearbyWifiDevices.request();
      if (!nearbyStatus.isGranted) {
        debugPrint(
          'Nearby Wi-Fi permission not granted; continuing with location permission',
        );
      }
    } catch (e) {
      // Older Android versions or older plugin implementations may not expose
      // this permission. Location permission is still the required fallback.
      debugPrint('Nearby Wi-Fi permission request not available: $e');
    }

    return true;
  }

  static Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return true;
    final locationStatus = await Permission.locationWhenInUse.status;
    return locationStatus.isGranted;
  }

  static Future<WifiScanResult> performScan() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('Wi-Fi permissions not granted; returning an empty scan');
      }
    }

    final deviceId = await PrivacyUtils.getDeviceId();

    try {
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) {
        debugPrint('Cannot get scanned results yet: $canGet');
      }
    } catch (e) {
      debugPrint('Error checking Wi-Fi scan capability: $e');
    }

    try {
      final canStart = await WiFiScan.instance.canStartScan();
      if (canStart == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
      } else {
        debugPrint('Cannot start a fresh Wi-Fi scan: $canStart');
      }
    } catch (e) {
      // Continue and try cached results. This is common because Android
      // throttles repeated scans.
      debugPrint('Wi-Fi startScan error; trying cached results: $e');
    }

    await Future<void>.delayed(AppConfig.scanWaitTime);

    List<WiFiAccessPoint> results = const <WiFiAccessPoint>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        results = await WiFiScan.instance.getScannedResults();
        if (results.isNotEmpty) break;
      } catch (e) {
        debugPrint('getScannedResults attempt ${attempt + 1} failed: $e');
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    final accessPoints = <WifiReading>[];
    for (final network in results) {
      try {
        final bssid = network.bssid.trim();
        if (bssid.isEmpty) continue;
        accessPoints.add(
          WifiReading(
            bssid: bssid,
            rssi: network.level,
            frequency: network.frequency,
            ssid: network.ssid,
          ),
        );
      } catch (e) {
        debugPrint('Error parsing Wi-Fi access point: $e');
      }
    }

    accessPoints.sort((a, b) => b.rssi.compareTo(a.rssi));
    debugPrint('Wi-Fi scan completed: ${accessPoints.length} APs');

    return WifiScanResult(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      accessPoints: accessPoints,
    );
  }

  static Future<WifiScanResult> performSimulatedScan() async {
    final deviceId = await PrivacyUtils.getDeviceId();
    return WifiScanResult(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      accessPoints: <WifiReading>[
        WifiReading(
          bssid: '00:1A:2B:3C:4D:5E',
          rssi: -45,
          frequency: 2412,
        ),
        WifiReading(
          bssid: '00:1A:2B:3C:4D:5F',
          rssi: -65,
          frequency: 2437,
        ),
      ],
    );
  }

  static Future<bool> canGetScannedResults() async {
    try {
      final canGet = await WiFiScan.instance.canGetScannedResults();
      return canGet == CanGetScannedResults.yes;
    } catch (e) {
      debugPrint('canGetScannedResults error: $e');
      return false;
    }
  }
}
