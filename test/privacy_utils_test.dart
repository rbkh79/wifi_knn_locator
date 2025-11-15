import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/privacy_utils.dart';

void main() {
  group('PrivacyUtils Tests', () {
    test('هش کردن MAC address باید یکتا باشد', () {
      const mac1 = '00:1A:2B:3C:4D:5E';
      const mac2 = '00:1A:2B:3C:4D:5F';

      final hash1 = PrivacyUtils.hashMacAddress(mac1);
      final hash2 = PrivacyUtils.hashMacAddress(mac2);

      expect(hash1, isNotEmpty);
      expect(hash2, isNotEmpty);
      expect(hash1, isNot(equals(hash2)), reason: 'MACهای مختلف باید هش‌های مختلف داشته باشند');
    });

    test('هش کردن MAC یکسان باید نتیجه یکسان بدهد', () {
      const mac = '00:1A:2B:3C:4D:5E';

      final hash1 = PrivacyUtils.hashMacAddress(mac);
      final hash2 = PrivacyUtils.hashMacAddress(mac);

      expect(hash1, equals(hash2), reason: 'MAC یکسان باید هش یکسان داشته باشد');
    });

    test('ماسک کردن MAC address باید بخشی از آن را نمایش دهد', () {
      const mac = '00:1A:2B:3C:4D:5E';

      final masked = PrivacyUtils.maskMacAddress(mac, visibleChars: 6);

      expect(masked, isNotEmpty);
      expect(masked, contains('X'), reason: 'باید بخشی از MAC ماسک شده باشد');
      expect(masked.length, greaterThan(6));
    });

    test('کوتاه کردن MAC address باید طول را محدود کند', () {
      const mac = '00:1A:2B:3C:4D:5E';

      final shortened = PrivacyUtils.shortenMacAddress(mac, maxLength: 10);

      expect(shortened.length, lessThanOrEqualTo(13)); // 10 + "..."
      expect(shortened, contains('...'));
    });

    test('کوتاه کردن MAC کوتاه باید تغییری ندهد', () {
      const mac = '00:1A:2B';

      final shortened = PrivacyUtils.shortenMacAddress(mac, maxLength: 20);

      expect(shortened, equals(mac));
    });
  });
}

