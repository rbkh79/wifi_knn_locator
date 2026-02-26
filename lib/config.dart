/// تنظیمات و پارامترهای قابل تنظیم اپلیکیشن
class AppConfig {
  // پارامترهای اسکن
  static const Duration scanInterval = Duration(seconds: 5);
  static const int minApCountForEvaluation = 3;
  static const Duration scanWaitTime = Duration(seconds: 2);

  // پارامترهای تحقیقاتی و عملکردی (استفاده در Research Mode)
  static const bool enableResearchMode = false; // نمایش معیارهای پیشرفته در UI
  static const bool logPerformanceMetrics = true; // ضبط زمان‌بندی عملیات در `performance_log`
  static const bool logEstimationDetails = true; // ذخیره جزئیات هر تخمین در `estimation_logs`

  // پارامترهای KNN
  static const int defaultK = 3;
  static const double kEpsilon = 0.0001; // ε برای وزن‌دهی در WKNN
  static const bool normalizeRssiPerDevice = true;
  static const int smoothingWindowSize = 3;
  static const String missingApStrategy = 'zero'; // 'zero' یا 'mean'
  static const int minK = 1;
  static const int maxK = 10;
  static const bool enableAdaptiveK = true;
  static const double adaptiveRadiusMeters = 4.0;
  static const int adaptiveNeighborsPerK = 4;

  // پارامترهای پایگاه داده
  static const String databaseName = 'wifi_fingerprints.db';
  static const int databaseVersion = 5; // increased for research/performance logs

  // پارامترهای حریم خصوصی
  static const bool hashDeviceMac = true;
  static const bool showFullMacAddresses = false; // نمایش کامل MAC یا بخشی از آن
  static const String userIdKey = 'user_uuid';
  static const String privacySalt = 'research_salt_2026'; // نمکی برای SHA-256

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

  // پارامترهای ترکیب Indoor/Outdoor
  static const double wifiWeightAlpha = 0.7; // α برای ترکیب نمرات Wi‑Fi و BTS زمانی که داخل هستیم
  static const bool enableCellClustering = true;
  static const double cellClusterRadiusKm = 1.0;

  // تنظیمات موقعیت جغرافیایی
  static const String useGeolocationKey = 'use_geolocation';
  static const bool defaultUseGeolocation = true; // به صورت پیش‌فرض فعال است

  // تنظیمات بهبود KNN
  static const bool useRssiWeighting = true; // وزن‌دهی RSSI
  static const bool useNoiseFiltering = true; // فیلتر نویز
  static const int minApOccurrencePercent = 70; // حداقل درصد تکرار AP برای ذخیره
  static const int validationScanCount = 3; // تعداد اسکن برای validation
  static const double maxRssiVariance = 15.0; // حداکثر واریانس RSSI برای validation (dBm)
}

