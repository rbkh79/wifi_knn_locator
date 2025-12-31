# اپلیکیشن موقعیت‌یابی یکپارچه با Wi-Fi و KNN

یک اپلیکیشن موبایل Flutter برای موقعیت‌یابی یکپارچه (Indoor/Outdoor/Hybrid Localization) با استفاده از اسکن Wi-Fi (RSSI + MAC)، دکل‌های مخابراتی (Cell Towers) و الگوریتم K-Nearest Neighbors (KNN).

## ویژگی‌ها

### مکان‌یابی
- ✅ **مکان‌یابی Indoor**: با استفاده از Wi-Fi Fingerprinting و الگوریتم KNN
- ✅ **مکان‌یابی Outdoor**: با استفاده از دکل‌های مخابراتی (Cell Towers)
- ✅ **مکان‌یابی یکپارچه (Unified)**: ترکیب خودکار Indoor و Outdoor
- ✅ **تشخیص خودکار محیط**: Indoor/Outdoor/Hybrid/Unknown
- ✅ **الگوریتم KNN قابل تنظیم**: با Adaptive K و وزن‌دهی RSSI

### مسیر و پیش‌بینی
- ✅ **ردیابی مسیر (Trajectory Tracking)**: ذخیره و نمایش مسیر حرکت
- ✅ **پیش‌بینی مسیر (Path Prediction)**: پیش‌بینی موقعیت‌های آینده با مدل Markov
- ✅ **نمایش مسیر روی نقشه**: با رنگ‌بندی بر اساس نوع محیط

### رابط کاربری
- ✅ **نقشه تعاملی**: افزودن نقاط مرجع با لمس نقشه (flutter_map)
- ✅ **نمایش وضعیت محیط**: نمایشگر بصری Indoor/Outdoor/Hybrid
- ✅ **نمایش پیش‌بینی**: نمایش نتایج پیش‌بینی مسیر
- ✅ **رابط کاربری Material Design 3**: مدرن و کاربرپسند

### داده و ذخیره‌سازی
- ✅ **پایگاه داده آفلاین SQLite**: ذخیره اثرانگشت‌ها و تاریخچه
- ✅ **ثبت خودکار اسکن‌ها**: لاگ تمام اسکن‌های Wi-Fi و نتایج KNN
- ✅ **خروجی داده (Data Export)**: خروجی CSV و به‌اشتراک‌گذاری
- ✅ **تنظیمات قابل ذخیره**: ذخیره تنظیمات کاربر

### حریم خصوصی و امنیت
- ✅ **هش کردن MAC دستگاه**: با SHA-256 برای حفظ حریم خصوصی
- ✅ **ماسک کردن MAC**: نمایش جزئی MAC addressها
- ✅ **پنل شفافیت**: نمایش اطلاعات حریم خصوصی
- ✅ **ذخیره محلی**: تمام داده‌ها در دستگاه کاربر

### سایر ویژگی‌ها
- ✅ **حالت آموزش (Training Mode)**: جمع‌آوری داده‌های اثرانگشت
- ✅ **تحلیل مسیر (Path Analysis)**: تحلیل الگوهای حرکت
- ✅ **محاسبه اعتماد (Confidence Calculation)**: محاسبه دقیق ضریب اطمینان
- ✅ **تست‌های واحد**: برای ماژول‌های اصلی

## تشخیص محیط (Indoor/Outdoor Detection)

اپلیکیشن به صورت خودکار نوع محیط را تشخیص می‌دهد و بهترین روش مکان‌یابی را انتخاب می‌کند:

### محیط بسته (Indoor)
محیط به عنوان **Indoor** تشخیص داده می‌شود اگر:
- **حداقل 3 نقطه دسترسی Wi-Fi** شناسایی شود
- **قدرت سیگنال Wi-Fi > 0.3** باشد

**محاسبه قدرت Wi-Fi:**
- 60% میانگین قدرت سیگنال (RSSI): از -100 dBm (ضعیف) تا -50 dBm (عالی)
- 40% تعداد نقاط دسترسی: 3+ نقطه = امتیاز کامل

**مثال:**
- میانگین RSSI: -70 dBm → امتیاز: 0.6
- تعداد AP: 5 → امتیاز: 1.0
- قدرت کل: (0.6 × 0.6) + (1.0 × 0.4) = 0.76 ✅

### محیط باز (Outdoor)
محیط به عنوان **Outdoor** تشخیص داده می‌شود اگر:
- **حداقل 1 دکل مخابراتی** شناسایی شود

در این حالت از مکان‌یابی مبتنی بر دکل‌های مخابراتی (Cell Towers) استفاده می‌شود.

### حالت ترکیبی (Hybrid)
زمانی که **هر دو** شرط Indoor و Outdoor برقرار باشد:
- از هر دو روش مکان‌یابی استفاده می‌شود (Wi-Fi + Cell Towers)
- نتایج با وزن‌دهی ترکیب می‌شوند (پیش‌فرض: 70% Indoor + 30% Outdoor)
- دقت بالاتری در محیط‌های مرزی (مثل ورودی ساختمان) ارائه می‌دهد

### حالت نامشخص (Unknown)
زمانی که هیچ یک از شرایط بالا برقرار نباشد:
- نتیجه مکان‌یابی نامعتبر تلقی می‌شود
- به کاربر نمایش داده نمی‌شود
- کاربر باید به نقطه‌ای با سیگنال بهتر منتقل شود

## معماری سیستم

### ساختار ماژولار

```
lib/
├── config.dart                      # تنظیمات و پارامترهای قابل تنظیم
├── data_model.dart                  # مدل‌های داده (WifiReading, FingerprintEntry, LocationEstimate, ...)
├── wifi_scanner.dart                # ماژول اسکن Wi-Fi
├── cell_scanner.dart                # ماژول اسکن دکل‌های مخابراتی
├── local_database.dart              # مدیریت پایگاه داده SQLite
├── knn_localization.dart            # پیاده‌سازی الگوریتم KNN
├── main.dart                        # رابط کاربری اصلی
├── services/
│   ├── fingerprint_service.dart     # سرویس مدیریت اثرانگشت‌ها
│   ├── indoor_localization_service.dart    # سرویس مکان‌یابی Indoor
│   ├── outdoor_localization_service.dart   # سرویس مکان‌یابی Outdoor
│   ├── unified_localization_service.dart   # سرویس مکان‌یابی یکپارچه
│   ├── trajectory_service.dart      # سرویس ردیابی مسیر
│   ├── path_prediction_service.dart # سرویس پیش‌بینی مسیر
│   ├── movement_prediction_service.dart    # سرویس پیش‌بینی حرکت
│   ├── data_logger_service.dart     # سرویس ثبت خودکار داده‌ها
│   ├── data_export_service.dart     # سرویس خروجی داده
│   ├── location_service.dart        # سرویس موقعیت‌یابی
│   ├── settings_service.dart        # سرویس تنظیمات
│   ├── location_confidence_service.dart    # سرویس محاسبه اعتماد
│   ├── path_analysis_service.dart   # سرویس تحلیل مسیر
│   ├── fingerprint_validator.dart   # سرویس اعتبارسنجی اثرانگشت
│   ├── auto_csv_service.dart        # سرویس خودکار CSV
│   └── map_reference_point_picker.dart     # انتخاب نقطه مرجع از نقشه
├── widgets/
│   ├── environment_indicator.dart   # نمایشگر وضعیت محیط
│   ├── trajectory_display.dart      # نمایش مسیر
│   └── prediction_display.dart      # نمایش پیش‌بینی
└── utils/
    └── privacy_utils.dart           # ابزارهای حریم خصوصی (هش MAC)
```

### جریان داده‌ها

```
1. اسکن Wi-Fi + Cell Towers (wifi_scanner.dart + cell_scanner.dart)
   ↓
2. WifiScanResult + CellScanResult (data_model.dart)
   ↓
3. Unified Localization Service
   ├─ Indoor Localization Service (Wi-Fi → KNN)
   └─ Outdoor Localization Service (Cell Towers → KNN)
   ↓
4. تشخیص محیط (Indoor/Outdoor/Hybrid)
   ↓
5. UnifiedLocalizationResult
   ↓
6. [حالت آموزش] → ذخیره در پایگاه داده (local_database.dart)
   [حالت آنلاین] → 
      ├─ نمایش در UI (main.dart)
      ├─ ذخیره در Trajectory Service
      ├─ پیش‌بینی مسیر (Path Prediction Service)
      └─ ثبت در Data Logger Service
```

## نصب و راه‌اندازی

### پیش‌نیازها

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Android Studio / Xcode (برای اجرا روی دستگاه)
- مجوز Location (برای Android)

### نصب وابستگی‌ها

```bash
flutter pub get
```

### اجرای اپلیکیشن

```bash
# Android
flutter run

# iOS
flutter run -d ios
```

## استفاده از اپلیکیشن

### حالت آنلاین (تخمین موقعیت)

1. **اجرای اسکن**: روی دکمه "اسکن WiFi" کلیک کنید
   - اپلیکیشن به صورت خودکار اسکن Wi-Fi و Cell Towers را انجام می‌دهد
2. **نمایش نتایج**: 
   - **موقعیت تخمینی**: عرض و طول جغرافیایی
   - **نوع محیط**: Indoor/Outdoor/Hybrid/Unknown
   - **ضریب اطمینان**: میزان اعتماد به نتیجه
   - **لیست شبکه‌های Wi-Fi**: مشاهده شده با RSSI
   - **نقشه**: نمایش موقعیت روی نقشه تعاملی
   - **مسیر حرکت**: نمایش مسیر ردیابی شده (در صورت فعال بودن)
   - **پیش‌بینی مسیر**: نمایش موقعیت‌های پیش‌بینی شده آینده

### حالت آموزش (Training Mode)

1. **فعال‌سازی حالت آموزش**: سوئیچ "حالت آموزش" را روشن کنید
2. **انتخاب نقطه مرجع**:
   - **روش 1**: لمس کردن نقشه برای انتخاب مختصات
   - **روش 2**: وارد کردن دستی مختصات
3. **ایستادن در نقطه مرجع**: در نقطه انتخاب شده بایستید
4. **اجرای اسکن**: روی دکمه "اسکن WiFi" کلیک کنید
   - در حالت Validation، چندین اسکن انجام می‌شود برای اطمینان از کیفیت
5. **وارد کردن اطلاعات**:
   - عرض جغرافیایی (Latitude) - در صورت استفاده از روش 2
   - طول جغرافیایی (Longitude) - در صورت استفاده از روش 2
   - لیبل ناحیه (اختیاری) - برای شناسایی راحت‌تر
6. **ذخیره اثرانگشت**: روی دکمه "ذخیره اثرانگشت" کلیک کنید

### ویژگی‌های اضافی

- **نمایش مسیر**: مسیر حرکت کاربر روی نقشه نمایش داده می‌شود
- **پیش‌بینی مسیر**: اپلیکیشن موقعیت‌های احتمالی آینده را پیش‌بینی می‌کند
- **خروجی داده**: امکان خروجی گرفتن داده‌ها به صورت CSV
- **تنظیمات**: امکان تنظیم استفاده از GPS، نمایش مسیر و سایر تنظیمات

### جمع‌آوری داده‌های آموزش

برای دقت بهتر در تخمین موقعیت:

1. **تعداد نقاط مرجع**: حداقل 10-20 نقطه در هر ناحیه
2. **فاصله نقاط**: 2-5 متر بین نقاط مرجع
3. **تنوع موقعیت**: نقاط را در گوشه‌ها، مرکز، و مسیرها قرار دهید
4. **تکرار اسکن**: در هر نقطه 2-3 بار اسکن انجام دهید
5. **برچسب‌گذاری**: از لیبل‌های معنادار استفاده کنید (مثلاً "اتاق 101"، "راهرو")

## الگوریتم KNN

### شبه‌کد (Pseudocode)

```
FUNCTION estimateLocation(scanResult, k):
    // 1. بارگذاری تمام اثرانگشت‌ها
    fingerprints = loadAllFingerprints()
    
    IF fingerprints.isEmpty:
        RETURN null
    
    // 2. محاسبه فاصله تا هر اثرانگشت
    distances = []
    FOR EACH fingerprint IN fingerprints:
        distance = calculateEuclideanDistance(
            scanResult.accessPoints,
            fingerprint.accessPoints
        )
        distances.append(distance, fingerprint)
    
    // 3. مرتب‌سازی بر اساس فاصله
    SORT distances BY distance ASCENDING
    
    // 4. انتخاب k همسایه نزدیک
    kNearest = distances[0:k]
    
    // 5. محاسبه موقعیت تخمینی (میانگین وزن‌دار)
    latSum = 0, lonSum = 0, weightSum = 0
    FOR EACH neighbor IN kNearest:
        weight = 1 / (neighbor.distance + 1)
        latSum += neighbor.latitude * weight
        lonSum += neighbor.longitude * weight
        weightSum += weight
    
    estimatedLat = latSum / weightSum
    estimatedLon = lonSum / weightSum
    
    // 6. محاسبه ضریب اطمینان
    avgDistance = AVERAGE(kNearest.distances)
    confidence = 1 / (1 + avgDistance / 100)
    
    // 7. تعیین لیبل ناحیه
    zoneLabel = determineZoneLabel(kNearest)
    
    RETURN LocationEstimate(
        latitude: estimatedLat,
        longitude: estimatedLon,
        confidence: confidence,
        zoneLabel: zoneLabel
    )
END FUNCTION

FUNCTION calculateEuclideanDistance(observed, fingerprint):
    // ساخت Map برای دسترسی سریع
    observedMap = MAP(observed, key: bssid, value: rssi)
    fingerprintMap = MAP(fingerprint, key: bssid, value: rssi)
    
    // جمع‌آوری تمام BSSID‌ها
    allBssids = UNION(observedMap.keys, fingerprintMap.keys)
    
    // محاسبه فاصله اقلیدسی
    distanceSquared = 0
    FOR EACH bssid IN allBssids:
        obsRssi = observedMap[bssid] OR -100
        fpRssi = fingerprintMap[bssid] OR -100
        diff = obsRssi - fpRssi
        distanceSquared += diff * diff
    
    RETURN SQRT(distanceSquared)
END FUNCTION
```

### محاسبه فاصله

الگوریتم از **فاصله اقلیدسی** استفاده می‌کند:

```
distance = √(Σ(RSSI_observed - RSSI_fingerprint)²)
```

برای BSSID‌هایی که در یکی از دو مجموعه وجود ندارند، مقدار پیش‌فرض `-100 dBm` استفاده می‌شود.

### محاسبه ضریب اطمینان

```
confidence = 1 / (1 + averageDistance / 100)
```

ضریب اطمینان بین 0.0 تا 1.0 است:
- **> 0.7**: اعتماد بالا
- **0.3 - 0.7**: اعتماد متوسط
- **< 0.3**: اعتماد پایین (نتیجه نمایش داده نمی‌شود)

## حریم خصوصی

### هش کردن MAC دستگاه

MAC address دستگاه کاربر قبل از ذخیره یا ارسال، با الگوریتم SHA-256 هش می‌شود:

```dart
hashedMac = SHA256(macAddress).substring(0, 16)
```

### نمایش شفاف

اپلیکیشن به کاربر نشان می‌دهد:
- شناسه هش‌شده دستگاه
- لیست MAC addressهای APهای مشاهده شده (با ماسک جزئی)
- RSSI و فرکانس هر AP

## تست‌ها

### اجرای تست‌ها

```bash
# تمام تست‌ها
flutter test

# تست خاص
flutter test test/knn_localization_test.dart
flutter test test/wifi_scanner_test.dart
flutter test test/privacy_utils_test.dart
```

### تست‌های موجود

- ✅ `knn_localization_test.dart`: تست الگوریتم KNN
- ✅ `wifi_scanner_test.dart`: تست ماژول اسکن Wi-Fi
- ✅ `privacy_utils_test.dart`: تست ابزارهای حریم خصوصی

## تنظیمات

فایل `lib/config.dart` شامل تمام پارامترهای قابل تنظیم است:

```dart
// پارامترهای اسکن
static const Duration scanInterval = Duration(seconds: 5);
static const int minApCountForEvaluation = 3;
static const Duration scanWaitTime = Duration(seconds: 2);

// پارامترهای KNN
static const int defaultK = 3;  // تعداد همسایه‌ها
static const int minK = 1;
static const int maxK = 10;
static const bool enableAdaptiveK = true;  // فعال‌سازی K تطبیقی
static const double adaptiveRadiusMeters = 4.0;
static const int adaptiveNeighborsPerK = 4;

// پارامترهای پایگاه داده
static const String databaseName = 'wifi_fingerprints.db';
static const int databaseVersion = 4;

// پارامترهای حریم خصوصی
static const bool hashDeviceMac = true;
static const bool showFullMacAddresses = false;

// پارامترهای UI
static const double defaultMapZoom = 15.0;
static const double minMapZoom = 5.0;
static const double maxMapZoom = 18.0;

// آستانه‌های RSSI
static const int excellentRssi = -50;  // dBm
static const int goodRssi = -60;
static const int fairRssi = -70;
static const int poorRssi = -80;

// پارامترهای اعتماد
static const double confidenceThreshold = 0.3;  // حداقل اعتماد برای نمایش
static const double minConfidence = 0.0;
static const double maxConfidence = 1.0;

// تنظیمات بهبود KNN
static const bool useRssiWeighting = true;  // وزن‌دهی RSSI
static const bool useNoiseFiltering = true;  // فیلتر نویز
static const int minApOccurrencePercent = 70;
static const int validationScanCount = 3;
static const double maxRssiVariance = 15.0;  // dBm
```

## ساختار پایگاه داده

### جداول اثرانگشت Wi-Fi

#### جدول `fingerprints`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| fingerprint_id | TEXT | شناسه اثرانگشت (UNIQUE) |
| latitude | REAL | عرض جغرافیایی |
| longitude | REAL | طول جغرافیایی |
| zone_label | TEXT | لیبل ناحیه (اختیاری) |
| session_id | TEXT | شناسه جلسه آموزش |
| context_id | TEXT | شناسه زمینه |
| created_at | TEXT | زمان ایجاد |
| device_id | TEXT | شناسه دستگاه |

#### جدول `access_points`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| fingerprint_id | TEXT | شناسه اثرانگشت (Foreign Key) |
| bssid | TEXT | MAC address (BSSID) |
| rssi | INTEGER | قدرت سیگنال (dBm) |
| frequency | INTEGER | فرکانس (MHz) |
| ssid | TEXT | نام شبکه |

### جداول اثرانگشت Cell Towers

#### جدول `cell_fingerprints`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| fingerprint_id | TEXT | شناسه اثرانگشت (UNIQUE) |
| latitude | REAL | عرض جغرافیایی |
| longitude | REAL | طول جغرافیایی |
| zone_label | TEXT | لیبل ناحیه (اختیاری) |
| created_at | TEXT | زمان ایجاد |
| device_id | TEXT | شناسه دستگاه |

#### جدول `cell_towers`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| fingerprint_id | TEXT | شناسه اثرانگشت (Foreign Key) |
| cell_id | INTEGER | شناسه سلول |
| lac | INTEGER | Location Area Code |
| tac | INTEGER | Tracking Area Code |
| signal_strength | INTEGER | قدرت سیگنال (dBm) |
| mcc | INTEGER | Mobile Country Code |
| mnc | INTEGER | Mobile Network Code |

### جداول تاریخچه و لاگ

#### جدول `wifi_scans`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| device_id | TEXT | شناسه دستگاه |
| timestamp | TEXT | زمان اسکن |

#### جدول `wifi_scan_readings`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| scan_id | INTEGER | شناسه اسکن (Foreign Key) |
| bssid | TEXT | MAC address |
| rssi | INTEGER | قدرت سیگنال |
| frequency | INTEGER | فرکانس |
| ssid | TEXT | نام شبکه |

#### جدول `location_history`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| device_id | TEXT | شناسه دستگاه |
| latitude | REAL | عرض جغرافیایی |
| longitude | REAL | طول جغرافیایی |
| zone_label | TEXT | لیبل ناحیه |
| confidence | REAL | ضریب اطمینان |
| timestamp | TEXT | زمان ثبت |
| environment_type | TEXT | نوع محیط (indoor/outdoor/hybrid) |

#### جدول `raw_scans`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| device_id | TEXT | شناسه دستگاه |
| timestamp | TEXT | زمان اسکن |
| session_id | TEXT | شناسه جلسه |
| context_id | TEXT | شناسه زمینه |

#### جدول `raw_scan_readings`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| raw_scan_id | INTEGER | شناسه اسکن خام (Foreign Key) |
| bssid | TEXT | MAC address |
| rssi | INTEGER | قدرت سیگنال |
| frequency | INTEGER | فرکانس |
| ssid | TEXT | نام شبکه |

### جداول مدیریتی

#### جدول `training_sessions`

| ستون | نوع | توضیح |
|------|-----|-------|
| session_id | TEXT | شناسه جلسه (PRIMARY KEY) |
| context_id | TEXT | شناسه زمینه |
| started_at | TEXT | زمان شروع |
| finished_at | TEXT | زمان پایان |

### ایندکس‌ها

برای بهبود عملکرد، ایندکس‌های زیر ایجاد شده‌اند:
- `idx_fingerprint_id` روی `fingerprints(fingerprint_id)`
- `idx_ap_fingerprint_id` روی `access_points(fingerprint_id)`
- `idx_ap_bssid` روی `access_points(bssid)`
- `idx_scan_timestamp` روی `wifi_scans(timestamp)`

## عیب‌یابی

### مشکل: اسکن Wi-Fi کار نمی‌کند

**راه‌حل:**
1. بررسی مجوز Location (Android)
2. اطمینان از روشن بودن Wi-Fi
3. بررسی اینکه دستگاه از Wi-Fi scan پشتیبانی می‌کند

### مشکل: تخمین موقعیت دقیق نیست

**راه‌حل:**
1. تعداد اثرانگشت‌ها را افزایش دهید
2. نقاط مرجع را نزدیک‌تر به هم قرار دهید
3. در نقاط مختلف اسکن انجام دهید
4. مقدار k را تنظیم کنید (در config.dart)

### مشکل: ضریب اطمینان پایین است

**راه‌حل:**
1. تعداد APهای مشاهده شده را بررسی کنید (حداقل 3)
2. اثرانگشت‌های بیشتری در ناحیه اضافه کنید
3. از نقاط مرجع نزدیک‌تر استفاده کنید

## مجوزها

### Android

در `android/app/src/main/AndroidManifest.xml`:

**مجوزهای مکان‌یابی و Wi-Fi:**
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
```

**مجوزهای شبکه:**
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```

**مجوز اسکن دکل‌های مخابراتی (برای Outdoor Localization):**
```xml
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
```

**مجوزهای ذخیره‌سازی (برای خروجی CSV):**
```xml
<!-- برای Android 12 و پایین‌تر -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" 
    android:maxSdkVersion="32" />

<!-- برای Android 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
```

### iOS

در `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>برای اسکن Wi-Fi و مکان‌یابی نیاز به دسترسی مکان داریم</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>برای ردیابی مسیر نیاز به دسترسی مکان داریم</string>
```

**نکته مهم:** در Android 6.0+ (API 23+)، مجوزهای مکان باید به صورت runtime از کاربر درخواست شوند.

## توسعه‌دهندگان

### افزودن ویژگی جدید

1. ماژول مربوطه را در `lib/` پیدا کنید
2. تست واحد بنویسید
3. مستندات را به‌روزرسانی کنید

### ساختار کد

- **Separation of Concerns**: هر ماژول مسئولیت مشخصی دارد
- **Dependency Injection**: سرویس‌ها از طریق constructor تزریق می‌شوند
- **Error Handling**: تمام خطاها به درستی مدیریت می‌شوند
- **Type Safety**: استفاده از type-safe models

## مجوز (License)

این پروژه تحت مجوز MIT منتشر شده است.

## پشتیبانی

برای گزارش باگ یا پیشنهاد ویژگی جدید، لطفاً یک Issue ایجاد کنید.

---

## نکات مهم

- این اپلیکیشن برای موقعیت‌یابی یکپارچه (Indoor/Outdoor/Hybrid) طراحی شده است
- دقت مکان‌یابی به کیفیت داده‌های آموزش (Fingerprints) وابسته است
- برای دقت بهتر در محیط Indoor، حداقل 10-20 نقطه مرجع در هر ناحیه توصیه می‌شود
- مکان‌یابی Outdoor نیاز به شناسایی حداقل یک دکل مخابراتی دارد
- تمام داده‌ها به صورت محلی (Local) ذخیره می‌شوند و هیچ داده‌ای به سرور ارسال نمی‌شود
- این اپلیکیشن GPS-Free است و برای حفظ حریم خصوصی طراحی شده است
