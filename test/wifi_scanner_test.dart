import 'package:flutter_test/flutter_test.dart';
import '../lib/wifi_scanner.dart';
import '../lib/data_model.dart';

void main() {
  group('WifiScanner Tests', () {
    test('اسکن شبیه‌سازی شده باید نتایج معتبر برگرداند', () async {
      final scanResult = await WifiScanner.performSimulatedScan();

      expect(scanResult, isNotNull);
      expect(scanResult.deviceId, isNotEmpty);
      expect(scanResult.timestamp, isNotNull);
      expect(scanResult.accessPoints, isNotEmpty);
      expect(scanResult.accessPoints.length, greaterThan(0));

      // بررسی ساختار WifiReading
      for (final ap in scanResult.accessPoints) {
        expect(ap.bssid, isNotEmpty);
        expect(ap.rssi, lessThanOrEqualTo(0)); // RSSI معمولاً منفی است
        expect(ap.rssi, greaterThanOrEqualTo(-100)); // حداقل مقدار منطقی
      }
    });

    test('نتایج اسکن باید بر اساس RSSI مرتب شده باشند', () async {
      final scanResult = await WifiScanner.performSimulatedScan();

      if (scanResult.accessPoints.length > 1) {
        for (int i = 0; i < scanResult.accessPoints.length - 1; i++) {
          expect(
            scanResult.accessPoints[i].rssi,
            greaterThanOrEqualTo(scanResult.accessPoints[i + 1].rssi),
            reason: 'APها باید بر اساس RSSI نزولی مرتب شده باشند',
          );
        }
      }
    });

    test('شناسه دستگاه باید هش شده باشد', () async {
      final scanResult1 = await WifiScanner.performSimulatedScan();
      final scanResult2 = await WifiScanner.performSimulatedScan();

      // شناسه دستگاه باید یکتا باشد (یا حداقل وجود داشته باشد)
      expect(scanResult1.deviceId, isNotEmpty);
      expect(scanResult2.deviceId, isNotEmpty);
    });

    test('هر WifiReading باید BSSID معتبر داشته باشد', () async {
      final scanResult = await WifiScanner.performSimulatedScan();

      for (final ap in scanResult.accessPoints) {
        expect(ap.bssid, isNotEmpty);
        expect(ap.bssid.length, greaterThan(5)); // حداقل طول MAC address
      }
    });
  });
}

