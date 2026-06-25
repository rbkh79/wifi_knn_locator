# اپلیکیشن موقعیت‌یاب یکپارچه Wi-Fi و BTS با KNN

**فارسی** | [English](README.md)

یک اپلیکیشن موبایل **Flutter** برای **موقعیت‌یابی بدون GPS (Indoor/Outdoor/Hybrid)** که موقعیت جغرافیایی را از روی **Wi-Fi (RSSI + BSSID)** و **دکل‌های مخابراتی (BTS)** و با الگوریتم **K-Nearest Neighbors (KNN)** تخمین می‌زند. تمام حسگرها رادیویی‌اند — **هیچ سنسور حرکتی/IMU استفاده نمی‌شود** — و همه داده‌ها روی دستگاه می‌مانند.

> توضیح `pubspec.yaml`: *"A Flutter app that estimates geographic location using WiFi BSSIDs and KNN algorithm."*

---

## ✨ ویژگی‌ها

### موقعیت‌یابی
- **Wi-Fi Fingerprinting + KNN** برای موقعیت‌یابی داخل ساختمان (فاصله اقلیدسی وزن‌دار روی بردارهای RSSI)
- **اسکن دکل مخابراتی (BTS)** از طریق `TelephonyManager` بومی اندروید (2G/3G/4G/5G، سلول سرو‌دهنده + همسایه)
- **پشتیبانی از دو سیم‌کارت** (مثل Poco X3 Pro) — اسکن خودکار همه سیم‌کارت‌های فعال
- **تشخیص خودکار نوع محیط**: `Indoor` / `Outdoor` / `Hybrid` / `Unknown`
- **ترکیب یکپارچه (Fusion)**: میانگین وزن‌دار Wi-Fi و BTS (پیش‌فرض ۷۰٪ Indoor + ۳۰٪ Outdoor)
- **K تطبیقی**، وزن‌دهی RSSI، وزن‌دهی باند فرکانس (۵ گیگاهرتز وزن بالاتری نسبت به ۲.۴ گیگاهرتز دارد)

### پردازش سیگنال
- کاهش نویز RSSI: میانگین متحرک، فیلتر میانه، فیلتر کالمن
- حذف outliers (Z-score)، حذف هاسپات/APهای کم‌تکرار (`minApOccurrencePercent = 70`)
- **اعتبارسنجی اثرانگشت** هنگام آموزش (چند اسکن + بررسی واریانس RSSI، `validationScanCount = 3`)

### مسیر و پیش‌بینی
- **ردیابی مسیر** با نمایش هموارسازی‌شده روی نقشه
- **پیش‌بینی مسیر**: زنجیره مارکوف، N-gram و مبتنی بر سرعت
- **پیش‌بینی حرکت** (ناحیه بعدی) بر اساس تاریخچه موقعیت
- **تحلیل مسیر** (مسافت، زمان، تعداد نقاط)
- **سرویس اعتماد موقعیت**: بررسی فاصله GPS↔KNN + هشدار «موقعیت جدید»

### رابط کاربری
- **Material Design 3** تک‌صفحه‌ای (بخش‌ها: موقعیت دستگاه، اسکن Wi-Fi/BTS، نقشه، محیط، نتایج سیگنال، پیش‌بینی مسیر، دیباگ، تنظیمات، حالت پژوهشگر، شفافیت)
- **نقشه تعاملی** (`flutter_map` + OpenStreetMap): با لمس نقشه نقطه مرجع اضافه می‌شود — اسکن Wi-Fi + BTS به‌صورت خودکار انجام می‌شود
- صفحات **نقشه داخلی**، **تاریخچه موقعیت**، **تنظیمات**
- نمایش نقاط مرجع، تخمین KNN، مسیر کاربر، نشانگر GPS، پولی‌لاین مسیر و پیش‌بینی به همراه راهنمای رنگ

### داده و حریم خصوصی
- **پایگاه داده آفلاین SQLite** (`wifi_fingerprints.db`، نسخه ۵)
- **UUID یکتا برای هر نصب** در `shared_preferences`؛ شناسه دستگاه با **SHA-256** هش می‌شود
- **ماسک کردن BSSID** در رابط کاربری + پنل شفافیت
- **خروجی خودکار CSV** از هر اسکن (Wi-Fi + BTS + GPS + تخمین KNN)
- منبع اثرانگشت: نقاط آموزش روی دستگاه + `assets/wifi_fingerprints.csv` / `assets/indoor_maps/`
- بدون نیاز به بک‌اند (`backendUrl = null`)؛ هیچ داده خامی دستگاه را ترک نمی‌کند

---

## 🏗 معماری

### ساختار اپ

```
lib/
├── main.dart                        # رابط کاربری تک‌صفحه‌ای Material 3
├── config.dart                      # AppConfig — همه پارامترهای قابل تنظیم
├── data_model.dart                  # WifiReading, FingerprintEntry, LocationEstimate, ...
├── wifi_scanner.dart                # ماژول اسکن Wi-Fi
├── wifi_service.dart
├── cell_scanner.dart                # ماژول اسکن دکل‌های مخابراتی
├── bts_service.dart                 # تخمین موقعیت از BTS
├── hybrid_fusion_service.dart       # ترکیب وزن‌دار Wi-Fi + BTS
├── knn_localization.dart            # الگوریتم KNN (اقلیدسی وزن‌دار + K تطبیقی)
├── local_database.dart              # مدیریت SQLite
├── database_helper.dart
├── gps_service.dart
├── error_analysis_widget.dart
├── map_screen.dart
├── models/
│   └── environment_type.dart
├── theme/  app_theme.dart
├── ui/
│   ├── app_theme.dart
│   ├── indoor_map_page.dart
│   ├── location_history_screen.dart
│   ├── settings_screen.dart
│   └── single_page_home.dart
├── services/
│   ├── fingerprint_service.dart           # ذخیره/بارگذاری اثرانگشت
│   ├── fingerprint_validator.dart         # اعتبارسنجی چند اسکنه
│   ├── indoor_localization_service.dart   # Wi-Fi → KNN
│   ├── outdoor_localization_service.dart  # BTS → KNN
│   ├── unified_localization_service.dart  # انتخاب خودکار Indoor/Outdoor/Hybrid
│   ├── trajectory_service.dart            # ردیابی + هموارسازی مسیر
│   ├── path_prediction_service.dart       # مارکوف / N-gram / سرعت
│   ├── trajectory_prediction_service.dart
│   ├── prediction_service.dart
│   ├── movement_prediction_service.dart   # ناحیه بعدی (مارکوف)
│   ├── path_analysis_service.dart         # آمار مسیر
│   ├── location_confidence_service.dart   # بررسی اعتماد GPS↔KNN
│   ├── research_analytics_service.dart
│   ├── motion_detection_service.dart
│   ├── data_logger_service.dart           # ثبت اسکن‌ها و تخمین‌ها
│   ├── data_export_service.dart
│   ├── auto_csv_service.dart              # خروجی خودکار CSV
│   ├── indoor_csv_manager.dart
│   ├── location_service.dart
│   ├── settings_service.dart
│   └── map_reference_point_picker.dart
├── widgets/
│   ├── environment_indicator.dart
│   ├── trajectory_display.dart
│   ├── prediction_display.dart
│   ├── coordinate_panel.dart
│   ├── operator_status_header.dart
│   ├── position_map_widget.dart
│   ├── position_marker.dart
│   └── signal_detail_sheet.dart
└── utils/
    ├── privacy_utils.dart            # هش SHA-256 مک
    ├── rssi_filter.dart              # فیلتر RSSI / کاهش نویز
    ├── permission_utils.dart
    └── profiler.dart
```

### لایه بومی اندروید

```
android/app/src/main/kotlin/com/example/wifi_knn_locator/
└── MainActivity.kt                  # اسکن بومی BTS از طریق TelephonyManager
```

### جریان داده‌ها

```
1. اسکن Wi-Fi + BTS (wifi_scanner.dart + cell_scanner.dart)  ── به‌صورت موازی
        ↓
2. WifiScanResult + CellScanResult (data_model.dart)
        ↓
3. UnifiedLocalizationService
       ├─ IndoorLocalizationService  (Wi-Fi → KNN)
       └─ OutdoorLocalizationService (BTS → KNN)
        ↓
4. تشخیص نوع محیط  →  Indoor / Outdoor / Hybrid / Unknown
        ↓
5. LocationConfidenceService  (فاصله GPS↔KNN، قابلیت اطمینان، هشدار «موقعیت جدید»)
        ↓
6. [حالت آموزش] → ذخیره اثرانگشت (با اعتبارسنجی) در SQLite
   [حالت آنلاین]   →
       ├─ نمایش در UI (main.dart)
       ├─ افزودن به TrajectoryService
       ├─ پیش‌بینی مسیر بعدی  (PathPredictionService)
       ├─ پیش‌بینی ناحیه بعدی  (MovementPredictionService)
       ├─ ثبت در DataLoggerService
       └─ خروجی CSV با AutoCsvService
```

---

## 🧠 تشخیص نوع محیط (مستخرج از کد)

| محیط | شرط |
|---|---|
| **Indoor** | `accessPointCount >= 3` **و** `wifiStrength > 0.3` که در آن `wifiStrength = rssiScore × 0.6 + apCountScore × 0.4` (RSSI از −100→0.0 تا −50→1.0) |
| **Outdoor** | حداقل یک دکل مخابراتی قابل اعتماد (سرو‌دهنده یا همسایه) |
| **Hybrid** | هم Indoor و هم Outdoor قابل اعتمار باشند → ترکیب وزن‌دار (پیش‌فرض ۷۰٪ Indoor + ۳۰٪ Outdoor) |
| **Unknown** | هیچ‌کدام قابل اعتماد نباشند → تخمین دور ریخته می‌شود (نمایش داده نمی‌شود) |

---

## 📐 الگوریتم KNN

**فاصله اقلیدسی وزن‌دار** روی بردارهای RSSI:

```
distance = √( Σ wᵢ · (RSSI_observed − RSSI_fingerprint)² )
```

- `wᵢ` ترکیبی از **قدرت سیگنال** (RSSI قوی‌تر → وزن بالاتر) و **باند فرکانس** است (۵ گیگاهرتز ≈ ۱.۳×، ۲.۴ گیگاهرتز = ۱.۰×)
- برای BSSID غایب در یک طرف، مقدار پیش‌فرض `−100 dBm` لحاظ می‌شود
- میانگین وزن‌دار k همسایه با وزن `1 / (distance + 1)`
- **K تطبیقی** (`minK=1 … maxK=10`، `defaultK=3`، `adaptiveRadiusMeters=4.0`)

**ضریب اطمینان:**

```
confidence = 1 − (minDistance / maxExpectedDistance)
```

نتیجه فقط در صورتی نمایش داده می‌شود که `confidence ≥ 0.3` (`confidenceThreshold`).

---

## 🚀 نصب و راه‌اندازی

### پیش‌نیازها
- Flutter SDK `>=3.0.0` (Dart `>=3.0.0 <4.0.0`)
- Android Studio / Xcode (یا فقط CLI)

### نصب وابستگی‌ها

```bash
flutter pub get
```

### اجرا / ساخت (فقط با CLI هم ممکن است)

```bash
flutter run                       # اجرا روی دستگاه/شبیه‌ساز متصل
flutter build apk --release       # APK نسخه نهایی
flutter build appbundle --release # AAB نسخه نهایی
```

اسکریپت‌های آماده در ریشه پروژه: `build_apk_simple.bat`، `build_aab.bat`، `build_apk_smart.bat`، …

---

## 📱 مجوزهای اندروید

در `android/app/src/main/AndroidManifest.xml`:

- **مکان**: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- **Wi-Fi**: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` (اندروید ۱۳+)
- **شبکه**: `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE`
- **تلفن (برای BTS)**: `READ_PHONE_STATE`, `READ_PRECISE_PHONE_STATE`, `READ_BASIC_PHONE_STATE` (اندروید ۱۳+)
- **حافظه**: `READ/WRITE_EXTERNAL_STORAGE` (≤ API 32)؛ `READ_MEDIA_IMAGES/VIDEO/AUDIO` (اندروید ۱۳+)

> ⚠️ در **اندروید ۱۳+** برای اسکن BTS هم مجوز **Location** و هم **Phone** لازم است و سرویس موقعیت دستگاه باید روشن باشد.

### عیب‌یابی BTS

1. هر دو مجوز **Location** و **Phone** را بدهید.
2. **سرویس موقعیت** دستگاه را روشن کنید (حتی برای حالت فقط BTS).
3. **سیم‌کارت** فعال وارد کنید و **حالت هواپیما** را خاموش کنید.
4. در **MIUI** موقعیت را روی «همیشه اجازه داده شود» بگذارید و بهینه‌سازی باتری را بررسی کنید.
5. **دو سیم‌کارت**: اپ همه سیم‌کارت‌های فعال را اسکن می‌کند — سیم‌کارت پیش‌فرض را در تنظیمات بررسی کنید.
6. لاگ‌ها: `adb logcat | grep BTS_Service`.

---

## 🧭 استفاده از اپ

### حالت آنلاین (تخمین موقعیت)
1. دکمه **«شروع اسکن Wi-Fi + BTS»** را بزنید.
2. اپ به‌صورت موازی Wi-Fi و BTS را اسکن می‌کند، موقعیت‌یابی یکپارچه را اجرا می‌کند و نمایش می‌دهد:
   - **عرض/طول جغرافیایی** تخمینی و **لیبل ناحیه**
   - **نوع محیط** (Indoor/Outdoor/Hybrid/Unknown) و **ضریب اطمینان**
   - شبکه‌های Wi-Fi شناسایی‌شده و فهرست BTS
   - موقعیت روی نقشه تعاملی، به همراه پولی‌لاین مسیر و پیش‌بینی
   - هشدار قابلیت اطمینان در صورت پایین بودن ضریب یا قرار داشتن در موقعیت جدید

### حالت آموزش (جمع‌آوری اثرانگشت)
1. **«حالت آموزش»** را فعال کنید.
2. **روش A** — نقشه را لمس کنید تا نقطه مرجع تعیین شود (اسکن Wi-Fi + BTS خودکار انجام می‌شود).
   **روش B** — عرض/طول جغرافیایی/لیبل ناحیه را دستی وارد کنید.
3. (اختیاری) اعتبارسنجی چند اسکنه با بررسی واریانس RSSI اجرا می‌شود.
4. دکمه **«ذخیره اثرانگشت»** (Floating Action Button) را بزنید.

### نکته‌هایی برای دقت بهتر
- ۱۰ تا ۲۰ نقطه مرجع در هر ناحیه، با فاصله ۲ تا ۵ متر.
- در هر نقطه ۲ تا ۳ بار اسکن کنید؛ از لیبل‌های معنادار استفاده کنید («اتاق ۱۰۱»، «راهرو»).

---

## 🗄 ساختار پایگاه داده (SQLite)

تمام جدول‌ها در `lib/local_database.dart` تعریف شده و با `sqflite` مدیریت می‌شوند.

| جدول | کاربرد |
|---|---|
| `fingerprints` | متادیتای اثرانگشت Wi-Fi (id, fingerprint_id, lat, lon, zone_label, session_id, context_id, device_id, created_at) |
| `access_points` | RSSI/frequency/SSID برای هر اثرانگشت |
| `cell_fingerprints` | متادیتای اثرانگشت BTS |
| `cell_towers` | cell_id, lac, tac, mcc, mnc, signal_strength برای هر اثرانگشت |
| `wifi_scans` / `wifi_scan_readings` | لاگ اسکن Wi-Fi |
| `raw_scans` / `raw_scan_readings` | لاگ اسکن خام (آگاه از session/context) |
| `location_history` | تخمین‌های ثبت‌شده (+ environment_type) |
| `training_sessions` | مدیریت جلسه/زمینه |

ایندکس‌ها: `idx_fingerprint_id`، `idx_ap_fingerprint_id`، `idx_ap_bssid`، `idx_scan_timestamp`.

---

## ⚙️ تنظیمات

تمام پارامترهای قابل تنظیم در `lib/config.dart` (`AppConfig`):

```dart
// اسکن
static const Duration scanInterval   = Duration(seconds: 5);
static const int minApCountForEvaluation = 3;
static const Duration scanWaitTime   = Duration(seconds: 2);

// KNN
static const int defaultK = 3;            // K تطبیقی
static const int minK = 1, maxK = 10;
static const bool enableAdaptiveK = true;
static const double adaptiveRadiusMeters = 4.0;
static const int adaptiveNeighborsPerK = 4;

// پایگاه داده
static const String databaseName = 'wifi_fingerprints.db';
static const int databaseVersion = 5;

// حریم خصوصی
static const bool hashDeviceMac = true;
static const bool showFullMacAddresses = false;

// نقشه
static const double defaultMapZoom = 15.0;
static const double minMapZoom = 5.0, maxMapZoom = 18.0;

// آستانه‌های RSSI (dBm)
static const int excellentRssi = -50, goodRssi = -60,
                 fairRssi = -70,    poorRssi = -80;

// اعتماد
static const double confidenceThreshold = 0.3;

// بهبودهای KNN
static const bool useRssiWeighting  = true;
static const bool useNoiseFiltering = true;
static const int minApOccurrencePercent = 70;
static const int validationScanCount    = 3;
static const double maxRssiVariance = 15.0; // dBm
```

---

## 🔒 حریم خصوصی

- برای هر نصب یک **UUID** تولید و در `shared_preferences` ذخیره می‌شود.
- شناسه دستگاه/مک پیش از ذخیره یا نمایش با **SHA-256** هش می‌شود.
- BSSIDها به‌صورت **ماسک‌شده** نمایش داده می‌شوند؛ پنل شفافیت مشخص می‌کند چه چیزی جمع‌آوری می‌شود.
- به‌صورت پیش‌فرض **بدون بک‌اند** است (`backendUrl = null`)؛ همه داده‌ها محلی می‌مانند.

---

## 🧪 تست‌ها

```bash
flutter test                                    # همه تست‌ها
flutter test test/knn_localization_test.dart    # الگوریتم KNN
flutter test test/wifi_scanner_test.dart        # اسکنر Wi-Fi
flutter test test/privacy_utils_test.dart       # ابزارهای حریم خصوصی
flutter test test/integration_test.dart         # یکپارچه‌سازی
```

---

## 📄 مجوز

مجوز MIT — به `LICENSE` مراجعه کنید.

---

نسخه انگلیسی: [README.md](README.md).
