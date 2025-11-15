# اپلیکیشن موقعیت‌یابی داخلی با Wi-Fi و الگوریتم KNN

یک اپلیکیشن موبایل Flutter برای موقعیت‌یابی داخلی (Indoor Localization) با استفاده از اسکن Wi-Fi (RSSI + MAC) و الگوریتم K-Nearest Neighbors (KNN).

## ویژگی‌ها

- ✅ اسکن دوره‌ای نقاط دسترسی Wi-Fi (Access Points)
- ✅ ثبت داده‌های کامل: MAC (BSSID)، RSSI، فرکانس، SSID
- ✅ هش کردن MAC دستگاه کاربر برای حفظ حریم خصوصی
- ✅ پایگاه داده آفلاین SQLite برای ذخیره اثرانگشت‌ها
- ✅ الگوریتم KNN برای تخمین موقعیت
- ✅ نمایش ضریب اطمینان (Confidence Score)
- ✅ حالت آموزش (Training Mode) برای جمع‌آوری داده
- ✅ رابط کاربری کاربرپسند و شفاف
- ✅ نمایش شفاف اطلاعات حریم خصوصی
- ✅ تست‌های واحد برای ماژول‌های اصلی

## معماری سیستم

### ساختار ماژولار

```
lib/
├── config.dart                 # تنظیمات و پارامترهای قابل تنظیم
├── data_model.dart             # مدل‌های داده (WifiReading, FingerprintEntry, LocationEstimate)
├── wifi_scanner.dart           # ماژول اسکن Wi-Fi
├── local_database.dart         # مدیریت پایگاه داده SQLite
├── knn_localization.dart       # پیاده‌سازی الگوریتم KNN
├── main.dart                   # رابط کاربری اصلی
├── services/
│   └── fingerprint_service.dart # سرویس مدیریت اثرانگشت‌ها
└── utils/
    └── privacy_utils.dart      # ابزارهای حریم خصوصی (هش MAC)
```

### جریان داده‌ها

```
1. اسکن Wi-Fi (wifi_scanner.dart)
   ↓
2. WifiScanResult (data_model.dart)
   ↓
3. [حالت آموزش] → ذخیره در پایگاه داده (local_database.dart)
   [حالت آنلاین] → تخمین موقعیت با KNN (knn_localization.dart)
   ↓
4. LocationEstimate (data_model.dart)
   ↓
5. نمایش در UI (main.dart)
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
2. **نمایش نتایج**: 
   - موقعیت تخمینی (عرض و طول جغرافیایی)
   - ضریب اطمینان (Confidence)
   - لیست شبکه‌های Wi-Fi مشاهده شده
   - نمایش روی نقشه

### حالت آموزش (Training Mode)

1. **فعال‌سازی حالت آموزش**: سوئیچ "حالت آموزش" را روشن کنید
2. **ایستادن در نقطه مرجع**: در نقطه‌ای با مختصات شناخته‌شده بایستید
3. **اجرای اسکن**: روی دکمه "اسکن WiFi" کلیک کنید
4. **وارد کردن مختصات**:
   - عرض جغرافیایی (Latitude)
   - طول جغرافیایی (Longitude)
   - لیبل ناحیه (اختیاری)
5. **ذخیره اثرانگشت**: روی دکمه "ذخیره اثرانگشت" کلیک کنید

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
// پارامترهای KNN
static const int defaultK = 3;  // تعداد همسایه‌ها

// پارامترهای اسکن
static const Duration scanInterval = Duration(seconds: 5);
static const int minApCountForEvaluation = 3;

// پارامترهای اعتماد
static const double confidenceThreshold = 0.3;
```

## ساختار پایگاه داده

### جدول `fingerprints`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| fingerprint_id | TEXT | شناسه اثرانگشت |
| latitude | REAL | عرض جغرافیایی |
| longitude | REAL | طول جغرافیایی |
| zone_label | TEXT | لیبل ناحیه (اختیاری) |
| created_at | TEXT | زمان ایجاد |
| device_id | TEXT | شناسه دستگاه |

### جدول `access_points`

| ستون | نوع | توضیح |
|------|-----|-------|
| id | INTEGER | شناسه یکتا |
| fingerprint_id | TEXT | شناسه اثرانگشت (Foreign Key) |
| bssid | TEXT | MAC address (BSSID) |
| rssi | INTEGER | قدرت سیگنال |
| frequency | INTEGER | فرکانس (MHz) |
| ssid | TEXT | نام شبکه |

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

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

### iOS

در `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>برای اسکن Wi-Fi نیاز به دسترسی مکان داریم</string>
```

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

**نکته**: این اپلیکیشن برای موقعیت‌یابی داخلی طراحی شده است و دقت آن به کیفیت داده‌های آموزش وابسته است.
