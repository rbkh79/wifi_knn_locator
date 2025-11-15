import 'package:shared_preferences/shared_preferences.dart';
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
    };
  }
}

