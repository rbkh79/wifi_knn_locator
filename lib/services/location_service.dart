import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

/// سرویس مدیریت موقعیت جغرافیایی دستگاه
class LocationService {
  /// بررسی و درخواست مجوزهای موقعیت
  static Future<bool> checkAndRequestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  /// دریافت موقعیت فعلی دستگاه
  /// ابتدا با دقت پایین (سریع) امتحان می‌کند، سپس با دقت بالا
  static Future<Position?> getCurrentPosition() async {
    try {
      bool hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        debugPrint('❌ GPS: no permission');
        return null;
      }

      // مرحله ۱: دریافت آخرین موقعیت شناخته‌شده (فوری، بدون انتظار)
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          final age = DateTime.now().difference(lastKnown.timestamp);
          // اگر کمتر از ۵ دقیقه قدیمی باشد، قبول می‌کنیم
          if (age.inMinutes < 5) {
            debugPrint('✓ GPS: using last known position (${age.inSeconds}s old)');
            return lastKnown;
          }
        }
      } catch (e) {
        debugPrint('GPS last known error: $e');
      }

      // مرحله ۲: دریافت موقعیت جدید با دقت پایین (سریع‌تر، ۵ ثانیه)
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 5),
        );
        debugPrint('✓ GPS (low accuracy): ${position.latitude}, ${position.longitude}');
        return position;
      } on TimeoutException catch (_) {
        debugPrint('GPS low accuracy timeout, trying medium...');
      } catch (e) {
        debugPrint('GPS low accuracy error: $e');
      }

      // مرحله ۳: دریافت موقعیت با دقت متوسط (۱۵ ثانیه)
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        );
        debugPrint('✓ GPS (medium accuracy): ${position.latitude}, ${position.longitude}');
        return position;
      } on TimeoutException catch (_) {
        debugPrint('GPS medium accuracy also timed out');
      } catch (e) {
        debugPrint('GPS medium accuracy error: $e');
      }

      debugPrint('⚠ GPS: all attempts failed');
      return null;
    } catch (e) {
      debugPrint('❌ GPS unexpected error: $e');
      return null;
    }
  }

  /// بررسی اینکه آیا مجوز موقعیت داده شده است
  static Future<bool> hasLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// بررسی اینکه آیا سرویس موقعیت فعال است
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
}