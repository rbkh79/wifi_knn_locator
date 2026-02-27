import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';

/// سرویس مدیریت تنظیمات اپلیکیشن
class SettingsService {
  static SharedPreferences? _prefs;

  /// مقداردهی اولیه
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// دریافت وضعیت استفاده از موقعیت جغرافیایی
  static Future<bool> getUseGeolocation() async {
    await init();
    return _prefs?.getBool(AppConfig.useGeolocationKey) ??
        AppConfig.defaultUseGeolocation;
  }

  /// تنظیم استفاده از موقعیت جغرافیایی
  static Future<bool> setUseGeolocation(bool value) async {
    await init();
    return await _prefs?.setBool(AppConfig.useGeolocationKey, value) ?? false;
  }

  /// دریافت تمام تنظیمات
  static Future<Map<String, dynamic>> getAllSettings() async {
    await init();
    return {
      'useGeolocation': await getUseGeolocation(),
      'userId': await getOrCreateUserId(),
    };
  }

  /// دریافت یا ایجاد شناسه یکتای کاربر
  static Future<String> getOrCreateUserId() async {
    await init();
    final existing = _prefs?.getString(AppConfig.userIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final uuid = const Uuid().v4();
    await _prefs?.setString(AppConfig.userIdKey, uuid);
    return uuid;
  }
}










