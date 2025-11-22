import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_knn_locator/data_model.dart';
import 'package:wifi_knn_locator/local_database.dart';
import 'package:wifi_knn_locator/knn_localization.dart';
import 'package:wifi_knn_locator/utils/rssi_filter.dart';
import 'package:wifi_knn_locator/services/fingerprint_validator.dart';

/// Integration Tests برای اطمینان از عملکرد صحیح سیستم
void main() {
  group('Integration Tests', () {
    late LocalDatabase database;
    late KnnLocalization knnLocalization;

    setUp(() async {
      database = LocalDatabase.instance;
      knnLocalization = KnnLocalization(database);
      await database.clearAll();
    });

    tearDown(() async {
      await database.clearAll();
    });

    test('ذخیره و بازیابی Fingerprint', () async {
      final fingerprint = FingerprintEntry(
        fingerprintId: 'test_fp_1',
        latitude: 35.6762,
        longitude: 51.4158,
        zoneLabel: 'Test Zone',
        accessPoints: [
          WifiReading(bssid: '00:1A:2B:3C:4D:5E', rssi: -45),
          WifiReading(bssid: '00:1A:2B:3C:4D:5F', rssi: -60),
        ],
        createdAt: DateTime.now(),
        deviceId: 'test_device',
      );

      await database.insertFingerprint(fingerprint);
      final retrieved = await database.getFingerprintById('test_fp_1');

      expect(retrieved, isNotNull);
      expect(retrieved!.latitude, equals(35.6762));
      expect(retrieved.longitude, equals(51.4158));
      expect(retrieved.zoneLabel, equals('Test Zone'));
      expect(retrieved.accessPoints.length, equals(2));
    });

    test('KNN تخمین موقعیت صحیح', () async {
      // افزودن چند fingerprint
      final fingerprints = [
        FingerprintEntry(
          fingerprintId: 'fp1',
          latitude: 35.6762,
          longitude: 51.4158,
          accessPoints: [
            WifiReading(bssid: '00:1A:2B:3C:4D:5E', rssi: -45),
            WifiReading(bssid: '00:1A:2B:3C:4D:5F', rssi: -60),
          ],
          createdAt: DateTime.now(),
          deviceId: 'test',
        ),
        FingerprintEntry(
          fingerprintId: 'fp2',
          latitude: 35.6800,
          longitude: 51.4200,
          accessPoints: [
            WifiReading(bssid: '00:1A:2B:3C:4D:5E', rssi: -50),
            WifiReading(bssid: '00:1A:2B:3C:4D:5F', rssi: -55),
          ],
          createdAt: DateTime.now(),
          deviceId: 'test',
        ),
      ];

      for (final fp in fingerprints) {
        await database.insertFingerprint(fp);
      }

      // اسکن مشابه
      final scanResult = WifiScanResult(
        deviceId: 'test',
        timestamp: DateTime.now(),
        accessPoints: [
          WifiReading(bssid: '00:1A:2B:3C:4D:5E', rssi: -47),
          WifiReading(bssid: '00:1A:2B:3C:4D:5F', rssi: -62),
        ],
      );

      final estimate = await knnLocalization.estimateLocation(scanResult, k: 2);

      expect(estimate, isNotNull);
      expect(estimate!.latitude, greaterThan(35.6760));
      expect(estimate.latitude, lessThan(35.6805));
      expect(estimate.confidence, greaterThan(0.0));
      expect(estimate.confidence, lessThanOrEqualTo(1.0));
    });

    test('RSSI Filter - Moving Average', () {
      final scanHistory = [
        [WifiReading(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -45)],
        [WifiReading(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -47)],
        [WifiReading(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -46)],
      ];

      final filtered = RssiFilter.applyMovingAverage(scanHistory);

      expect(filtered.length, equals(1));
      expect(filtered.first.bssid, equals('AA:BB:CC:DD:EE:FF'));
      expect(filtered.first.rssi, greaterThanOrEqualTo(-47));
      expect(filtered.first.rssi, lessThanOrEqualTo(-45));
    });

    test('RSSI Filter - Remove Temporary APs', () {
      final scanHistory = [
        [WifiReading(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -45)],
        [WifiReading(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -47)],
        [WifiReading(bssid: 'AA:BB:CC:DD:EE:FF', rssi: -46)],
        [WifiReading(bssid: '11:22:33:44:55:66', rssi: -70)], // فقط یک بار
      ];

      final filtered = RssiFilter.removeTemporaryAps(scanHistory, 70);

      expect(filtered.length, equals(1));
      expect(filtered.first.bssid, equals('AA:BB:CC:DD:EE:FF'));
    });

    test('RSSI Weight Calculation', () {
      final weight1 = RssiFilter.calculateRssiWeight(-45);
      final weight2 = RssiFilter.calculateRssiWeight(-70);

      expect(weight1, greaterThan(weight2)); // RSSI قوی‌تر = وزن بیشتر
      expect(weight1, greaterThan(0));
      expect(weight2, greaterThan(0));
    });

    test('RSSI Variance Calculation', () {
      final rssiValues = [-45, -47, -46, -45, -46];
      final variance = RssiFilter.calculateRssiVariance(rssiValues);

      expect(variance, greaterThanOrEqualTo(0));
      expect(variance, lessThan(10)); // واریانس کم برای RSSIهای مشابه
    });

    test('RSSI Convergence Check', () {
      final convergent = [-45, -46, -45, -46];
      final divergent = [-45, -60, -70, -80];

      expect(
        RssiFilter.isRssiConvergent(convergent, 15.0),
        isTrue,
      );
      expect(
        RssiFilter.isRssiConvergent(divergent, 15.0),
        isFalse,
      );
    });
  });
}





