import 'package:geolocator/geolocator.dart';
import 'database_helper.dart';

/// سرویس ساده برای فعال‌سازی GPS، دریافت مختصات و ذخیره تاریخچه
class GPSService {
  /// درخواست مجوز و گرفتن موقعیت فعلی
  static Future<Position?> activateGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // کاربر باید GPS را روشن کند
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5));

    // ذخیره در جدول gps_history
    await DatabaseHelper.insert('gps_history', {
      'timestamp': DateTime.now().toIso8601String(),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      // در صورت نیاز device_id از PrivacyUtils گرفته می‌شود
    });

    return position;
  }
}
