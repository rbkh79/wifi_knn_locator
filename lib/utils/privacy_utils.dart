import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../config.dart';

/// ابزارهای مربوط به حریم خصوصی

class PrivacyUtils {
  /// هش کردن MAC address برای حفظ حریم خصوصی
  static String hashMacAddress(String mac) {
    if (!AppConfig.hashDeviceMac) {
      return mac;
    }
    final bytes = utf8.encode(mac.toLowerCase());
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // 16 کاراکتر اول هش
  }

  /// نمایش MAC address به صورت جزئی (برای شفافیت)
  /// مثال: "00:1A:2B:XX:XX:XX"
  static String maskMacAddress(String mac, {int visibleChars = 6}) {
    if (AppConfig.showFullMacAddresses) {
      return mac;
    }
    if (mac.length <= visibleChars) {
      return mac;
    }
    final visible = mac.substring(0, visibleChars);
    final masked = 'X' * (mac.length - visibleChars);
    return '$visible:$masked';
  }

  /// نمایش MAC address به صورت کوتاه شده
  /// مثال: "00:1A:2B..."
  static String shortenMacAddress(String mac, {int maxLength = 12}) {
    if (mac.length <= maxLength) {
      return mac;
    }
    return '${mac.substring(0, maxLength)}...';
  }

  /// تولید شناسه یکتا برای دستگاه (بر اساس MAC هش‌شده)
  static Future<String> getDeviceId() async {
    // در Flutter، برای دریافت MAC واقعی نیاز به پکیج‌های native داریم
    // برای حال حاضر، از یک شناسه تصادفی استفاده می‌کنیم
    // در تولید واقعی، می‌توان از device_info_plus استفاده کرد
    try {
      // شبیه‌سازی MAC address (در تولید واقعی باید از دستگاه واقعی بگیریم)
      final simulatedMac = '00:${DateTime.now().millisecondsSinceEpoch.toRadixString(16).substring(0, 10)}';
      return hashMacAddress(simulatedMac);
    } catch (e) {
      // Fallback: استفاده از timestamp
      return hashMacAddress(DateTime.now().toIso8601String());
    }
  }
}

