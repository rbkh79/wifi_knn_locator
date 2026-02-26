import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../config.dart';
import '../services/settings_service.dart';

/// ابزارهای مربوط به حریم خصوصی

class PrivacyUtils {
  /// هش کردن MAC address برای حفظ حریم خصوصی
  static String hashMacAddress(String mac) {
    if (!AppConfig.hashDeviceMac) {
      return mac;
    }
    // اضافه کردن نمک قبل از هش برای جلوگیری از حملات پیش‌ساخته
    final salted = '${AppConfig.privacySalt}|${mac.toLowerCase()}';
    final bytes = utf8.encode(salted);
    final digest = sha256.convert(bytes);
    // برگرداندن تنها 4 کاراکتر اول تا حریم بیشتر حفظ شود
    return digest.toString().substring(0, 4);
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

  /// دریافت شناسه یکتا برای دستگاه/کاربر
  static Future<String> getDeviceId() async {
    // از shared_preferences استفاده می‌کنیم تا برای هر نصب شناسه ثابت داشته باشد
    final userId = await SettingsService.getOrCreateUserId();
    if (AppConfig.hashDeviceMac) {
      // استفاده از نمک و هش برای شناسه دستگاه
      final salted = '${AppConfig.privacySalt}|$userId';
      final bytes = utf8.encode(salted);
      final digest = sha256.convert(bytes);
      return digest.toString().substring(0, 16);
    }
    return userId;
  }
}

