/// تنظیمات و پارامترهای قابل تنظیم اپلیکیشن
class AppConfig {
  // پارامترهای اسکن
  static const Duration scanInterval = Duration(seconds: 5);
  static const int minApCountForEvaluation = 3;
  static const Duration scanWaitTime = Duration(seconds: 2);

  // پارامترهای KNN
  static const int defaultK = 3;
  static const int minK = 1;
  static const int maxK = 10;

  // پارامترهای پایگاه داده
  static const String databaseName = 'wifi_fingerprints.db';
  static const int databaseVersion = 1;

  // پارامترهای حریم خصوصی
  static const bool hashDeviceMac = true;
  static const bool showFullMacAddresses = false; // نمایش کامل MAC یا بخشی از آن

  // آدرس بک‌اند (اختیاری)
  static const String? backendUrl = null; // 'https://api.example.com'

  // پارامترهای UI
  static const double defaultMapZoom = 15.0;
  static const double minMapZoom = 5.0;
  static const double maxMapZoom = 18.0;

  // آدرس پیش‌فرض (تهران)
  static const double defaultLatitude = 35.6762;
  static const double defaultLongitude = 51.4158;

  // آستانه‌های RSSI
  static const int excellentRssi = -50;
  static const int goodRssi = -60;
  static const int fairRssi = -70;
  static const int poorRssi = -80;

  // تنظیمات اعتماد (Confidence)
  static const double minConfidence = 0.0;
  static const double maxConfidence = 1.0;
  static const double confidenceThreshold = 0.3; // حداقل اعتماد برای نمایش نتیجه
}

