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

  // --- New settings used by modern UI ---
  static const _kContinuousScanKey = 'continuous_scan';
  static const _kScanIntervalKey = 'scan_interval_seconds';
  static const _kMotionAwareKey = 'motion_aware_scanning';
  static const _kHashMacKey = 'hash_device_mac';
  static const _kStoreLocalOnlyKey = 'store_local_only';
  static const _kLocalizationStrategyKey = 'localization_strategy';

  static Future<bool> getContinuousScan() async {
    await init();
    return _prefs?.getBool(_kContinuousScanKey) ?? false;
  }

  static Future<bool> setContinuousScan(bool v) async {
    await init();
    if (_prefs == null) return false;
    return await _prefs!.setBool(_kContinuousScanKey, v);
  }

  static Future<int> getScanIntervalSeconds() async {
    await init();
    return _prefs?.getInt(_kScanIntervalKey) ?? AppConfig.scanInterval.inSeconds;
  }

  static Future<bool> setScanIntervalSeconds(int s) async {
    await init();
    if (_prefs == null) return false;
    return await _prefs!.setInt(_kScanIntervalKey, s);
  }

  static Future<bool> getUseMotionAwareScanning() async {
    await init();
    return _prefs?.getBool(_kMotionAwareKey) ?? true;
  }

  static Future<bool> setUseMotionAwareScanning(bool v) async {
    await init();
    if (_prefs == null) return false;
    return await _prefs!.setBool(_kMotionAwareKey, v);
  }

  static Future<bool> getHashDeviceMac() async {
    await init();
    return _prefs?.getBool(_kHashMacKey) ?? AppConfig.hashDeviceMac;
  }

  static Future<bool> setHashDeviceMac(bool v) async {
    await init();
    if (_prefs == null) return false;
    return await _prefs!.setBool(_kHashMacKey, v);
  }

  static Future<bool> getStoreLocalOnly() async {
    await init();
    return _prefs?.getBool(_kStoreLocalOnlyKey) ?? true;
  }

  static Future<bool> setStoreLocalOnly(bool v) async {
    await init();
    if (_prefs == null) return false;
    return await _prefs!.setBool(_kStoreLocalOnlyKey, v);
  }

  static Future<int> getLocalizationStrategy() async {
    await init();
    return _prefs?.getInt(_kLocalizationStrategyKey) ?? 1;
  }

  static Future<bool> setLocalizationStrategy(int v) async {
    await init();
    if (_prefs == null) return false;
    return await _prefs!.setInt(_kLocalizationStrategyKey, v);
  }
}










