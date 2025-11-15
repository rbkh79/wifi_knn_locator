# معماری سیستم - WiFi KNN Locator

## طراحی کلی سیستم

### 1. معماری کلی

سیستم به صورت **ماژولار** و **لایه‌ای** طراحی شده است:

```
┌─────────────────────────────────────────┐
│           UI Layer (main.dart)          │
│  - نمایش نتایج                         │
│  - دریافت ورودی کاربر                  │
│  - مدیریت حالت (Training/Online)       │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│      Service Layer                      │
│  - FingerprintService                   │
│  - KnnLocalization                      │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│      Data Layer                         │
│  - WifiScanner                          │
│  - LocalDatabase                        │
│  - PrivacyUtils                         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│      External Dependencies              │
│  - wifi_scan (Flutter plugin)           │
│  - sqflite (SQLite)                     │
│  - flutter_map (Map display)            │
└─────────────────────────────────────────┘
```

### 2. جریان داده‌ها

#### حالت آنلاین (Online Mode)

```
User Action: Click "Scan WiFi"
    ↓
WifiScanner.performScan()
    ↓
WifiScanResult {
    deviceId: hashed_mac,
    timestamp: now,
    accessPoints: [WifiReading...]
}
    ↓
KnnLocalization.estimateLocation(scanResult)
    ↓
Load all fingerprints from LocalDatabase
    ↓
Calculate distances to all fingerprints
    ↓
Select k nearest neighbors
    ↓
Calculate weighted average position
    ↓
Calculate confidence score
    ↓
LocationEstimate {
    latitude, longitude,
    confidence, zoneLabel,
    nearestNeighbors
}
    ↓
Display in UI (main.dart)
```

#### حالت آموزش (Training Mode)

```
User Action: Enable Training Mode
    ↓
User Action: Click "Scan WiFi"
    ↓
WifiScanner.performScan()
    ↓
WifiScanResult
    ↓
User Input: latitude, longitude, zoneLabel
    ↓
FingerprintService.saveFingerprint()
    ↓
Create FingerprintEntry {
    fingerprintId: unique_id,
    latitude, longitude,
    zoneLabel,
    accessPoints: [WifiReading...],
    createdAt, deviceId
}
    ↓
LocalDatabase.insertFingerprint()
    ↓
Save to SQLite database
    ↓
Update UI (fingerprint count)
```

### 3. ماژول‌ها

#### config.dart
- **مسئولیت**: نگهداری تمام پارامترهای قابل تنظیم
- **ویژگی‌ها**: 
  - پارامترهای KNN (k, thresholds)
  - پارامترهای اسکن (intervals, min AP count)
  - تنظیمات حریم خصوصی
  - تنظیمات UI

#### data_model.dart
- **مسئولیت**: تعریف ساختار داده‌ها
- **کلاس‌ها**:
  - `WifiReading`: یک نقطه دسترسی Wi-Fi
  - `WifiScanResult`: نتیجه یک اسکن کامل
  - `FingerprintEntry`: یک اثرانگشت در پایگاه داده
  - `LocationEstimate`: تخمین موقعیت با اعتماد
  - `DistanceRecord`: رکورد فاصله برای KNN

#### wifi_scanner.dart
- **مسئولیت**: اسکن Wi-Fi و مدیریت مجوزها
- **متدها**:
  - `requestPermissions()`: درخواست مجوزها
  - `checkPermissions()`: بررسی مجوزها
  - `performScan()`: اجرای اسکن واقعی
  - `performSimulatedScan()`: اسکن شبیه‌سازی شده (برای تست)

#### local_database.dart
- **مسئولیت**: مدیریت پایگاه داده SQLite
- **عملیات**:
  - `insertFingerprint()`: افزودن اثرانگشت
  - `getAllFingerprints()`: دریافت تمام اثرانگشت‌ها
  - `getFingerprintById()`: دریافت اثرانگشت خاص
  - `deleteFingerprint()`: حذف اثرانگشت
  - `clearAll()`: پاک کردن تمام داده‌ها

#### knn_localization.dart
- **مسئولیت**: پیاده‌سازی الگوریتم KNN
- **متدها**:
  - `estimateLocation()`: تخمین موقعیت اصلی
  - `_calculateDistance()`: محاسبه فاصله اقلیدسی
  - `_calculateConfidence()`: محاسبه ضریب اطمینان
  - `_determineZoneLabel()`: تعیین لیبل ناحیه

#### privacy_utils.dart
- **مسئولیت**: ابزارهای حریم خصوصی
- **متدها**:
  - `hashMacAddress()`: هش کردن MAC address
  - `maskMacAddress()`: ماسک کردن MAC برای نمایش
  - `shortenMacAddress()`: کوتاه کردن MAC
  - `getDeviceId()`: دریافت شناسه هش‌شده دستگاه

#### services/fingerprint_service.dart
- **مسئولیت**: مدیریت اثرانگشت‌ها (Training Mode)
- **متدها**:
  - `saveFingerprint()`: ذخیره اثرانگشت جدید
  - `getAllFingerprints()`: دریافت تمام اثرانگشت‌ها
  - `deleteFingerprint()`: حذف اثرانگشت
  - `getFingerprintCount()`: تعداد اثرانگشت‌ها

## شبه‌کد (Pseudocode)

### الگوریتم KNN - حالت آنلاین

```
FUNCTION estimateLocation(scanResult: WifiScanResult, k: Integer) -> LocationEstimate:
    // 1. بارگذاری اثرانگشت‌ها
    fingerprints = database.getAllFingerprints()
    
    IF fingerprints.isEmpty:
        RETURN null
    
    // 2. بررسی حداقل تعداد AP
    IF scanResult.accessPoints.length < MIN_AP_COUNT:
        RETURN null
    
    // 3. محاسبه فاصله تا هر اثرانگشت
    distances = []
    FOR EACH fingerprint IN fingerprints:
        distance = calculateEuclideanDistance(
            scanResult.accessPoints,
            fingerprint.accessPoints
        )
        distances.append({
            distance: distance,
            fingerprint: fingerprint,
            index: current_index
        })
    
    // 4. مرتب‌سازی بر اساس فاصله
    SORT distances BY distance ASCENDING
    
    // 5. انتخاب k همسایه نزدیک
    kNearest = distances[0:min(k, distances.length)]
    
    IF kNearest.isEmpty:
        RETURN null
    
    // 6. محاسبه موقعیت تخمینی (میانگین وزن‌دار)
    latSum = 0.0
    lonSum = 0.0
    weightSum = 0.0
    
    FOR EACH neighbor IN kNearest:
        weight = 1.0 / (neighbor.distance + 1.0)  // +1 برای جلوگیری از تقسیم بر صفر
        latSum += neighbor.fingerprint.latitude * weight
        lonSum += neighbor.fingerprint.longitude * weight
        weightSum += weight
    
    IF weightSum == 0:
        RETURN null
    
    estimatedLat = latSum / weightSum
    estimatedLon = lonSum / weightSum
    
    // 7. محاسبه میانگین فاصله
    avgDistance = AVERAGE(kNearest.distances)
    
    // 8. محاسبه ضریب اطمینان
    confidence = calculateConfidence(avgDistance, kNearest.distances)
    
    // 9. تعیین لیبل ناحیه
    zoneLabel = determineZoneLabel(kNearest.fingerprints)
    
    RETURN LocationEstimate(
        latitude: estimatedLat,
        longitude: estimatedLon,
        confidence: confidence,
        zoneLabel: zoneLabel,
        nearestNeighbors: kNearest.fingerprints,
        averageDistance: avgDistance
    )
END FUNCTION

FUNCTION calculateEuclideanDistance(
    observed: List[WifiReading],
    fingerprint: List[WifiReading]
) -> Double:
    // ساخت Map برای دسترسی سریع‌تر
    observedMap = {}
    FOR EACH ap IN observed:
        observedMap[ap.bssid] = ap.rssi
    
    fingerprintMap = {}
    FOR EACH ap IN fingerprint:
        fingerprintMap[ap.bssid] = ap.rssi
    
    // جمع‌آوری تمام BSSID‌ها (اتحاد دو مجموعه)
    allBssids = UNION(observedMap.keys, fingerprintMap.keys)
    
    // محاسبه فاصله اقلیدسی
    distanceSquared = 0.0
    DEFAULT_RSSI = -100  // مقدار پیش‌فرض برای APهای مشاهده نشده
    
    FOR EACH bssid IN allBssids:
        obsRssi = observedMap.get(bssid, DEFAULT_RSSI)
        fpRssi = fingerprintMap.get(bssid, DEFAULT_RSSI)
        diff = obsRssi - fpRssi
        distanceSquared += diff * diff
    
    RETURN SQRT(distanceSquared)
END FUNCTION

FUNCTION calculateConfidence(
    avgDistance: Double,
    distances: List[Double]
) -> Double:
    // نرمال‌سازی بر اساس فاصله
    normalizedDistance = 1.0 / (1.0 + avgDistance / 100.0)
    
    // محاسبه یکنواختی (consistency)
    IF distances.length > 1:
        mean = avgDistance
        variance = 0.0
        FOR EACH d IN distances:
            variance += (d - mean) * (d - mean)
        variance = variance / distances.length
        stdDev = SQRT(variance)
        
        // هرچه انحراف معیار کمتر باشد، اعتماد بیشتر است
        consistency = 1.0 / (1.0 + stdDev / 50.0)
        
        // ترکیب نرمال‌سازی فاصله و یکنواختی
        confidence = normalizedDistance * 0.7 + consistency * 0.3
    ELSE:
        confidence = normalizedDistance
    
    RETURN CLAMP(confidence, 0.0, 1.0)
END FUNCTION

FUNCTION determineZoneLabel(neighbors: List[FingerprintEntry]) -> String?:
    IF neighbors.isEmpty:
        RETURN null
    
    labelCounts = {}
    FOR EACH neighbor IN neighbors:
        IF neighbor.zoneLabel != null AND neighbor.zoneLabel != "":
            labelCounts[neighbor.zoneLabel] = 
                labelCounts.get(neighbor.zoneLabel, 0) + 1
    
    IF labelCounts.isEmpty:
        RETURN null
    
    // پیدا کردن لیبل با بیشترین تعداد
    mostCommonLabel = null
    maxCount = 0
    FOR EACH (label, count) IN labelCounts:
        IF count > maxCount:
            maxCount = count
            mostCommonLabel = label
    
    // اگر اکثریت (بیش از 50%) یک لیبل داشته باشند
    IF maxCount > neighbors.length / 2:
        RETURN mostCommonLabel
    
    RETURN null
END FUNCTION
```

### الگوریتم ذخیره اثرانگشت - حالت آموزش

```
FUNCTION saveFingerprint(
    latitude: Double,
    longitude: Double,
    zoneLabel: String?,
    scanResult: WifiScanResult?
) -> FingerprintEntry:
    // اگر اسکن ارائه نشده، یک اسکن جدید انجام می‌دهیم
    IF scanResult == null:
        scanResult = WifiScanner.performScan()
    
    // تولید شناسه یکتا
    fingerprintId = generateFingerprintId(latitude, longitude)
    
    // دریافت شناسه دستگاه (هش‌شده)
    deviceId = PrivacyUtils.getDeviceId()
    
    // ایجاد ورودی اثرانگشت
    fingerprint = FingerprintEntry(
        fingerprintId: fingerprintId,
        latitude: latitude,
        longitude: longitude,
        zoneLabel: zoneLabel,
        accessPoints: scanResult.accessPoints,
        createdAt: DateTime.now(),
        deviceId: deviceId
    )
    
    // ذخیره در پایگاه داده
    database.insertFingerprint(fingerprint)
    
    RETURN fingerprint
END FUNCTION

FUNCTION generateFingerprintId(lat: Double, lon: Double) -> String:
    timestamp = DateTime.now().millisecondsSinceEpoch
    RETURN "fp_" + lat.toString(6) + "_" + lon.toString(6) + "_" + timestamp
END FUNCTION
```

### الگوریتم اسکن Wi-Fi

```
FUNCTION performScan() -> WifiScanResult:
    // 1. بررسی مجوزها
    IF NOT checkPermissions():
        IF NOT requestPermissions():
            THROW Exception("Permission denied")
    
    // 2. دریافت شناسه دستگاه (هش‌شده)
    deviceId = PrivacyUtils.getDeviceId()
    
    // 3. شروع اسکن
    TRY:
        WiFiScan.instance.startScan()
    CATCH:
        // ادامه می‌دهیم حتی اگر خطا بدهد
    
    // 4. انتظار برای نتایج
    WAIT scanWaitTime
    
    // 5. دریافت نتایج
    results = null
    TRY:
        results = WiFiScan.instance.getScannedResults()
    CATCH:
        results = null
    
    // 6. تبدیل نتایج
    accessPoints = []
    IF results != null AND results.isNotEmpty:
        FOR EACH network IN results:
            bssid = network.bssid
            rssi = network.rssi OR network.level OR -100
            frequency = network.frequency
            ssid = network.ssid
            
            IF bssid != "":
                accessPoints.append(WifiReading(
                    bssid: bssid,
                    rssi: rssi,
                    frequency: frequency,
                    ssid: ssid
                ))
    
    // 7. مرتب‌سازی بر اساس RSSI (قوی‌ترین اول)
    SORT accessPoints BY rssi DESCENDING
    
    RETURN WifiScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        accessPoints: accessPoints
    )
END FUNCTION
```

## ساختار پایگاه داده

### Schema

```sql
-- جدول اثرانگشت‌ها
CREATE TABLE fingerprints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fingerprint_id TEXT UNIQUE NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    zone_label TEXT,
    created_at TEXT NOT NULL,
    device_id TEXT
);

-- جدول نقاط دسترسی Wi-Fi
CREATE TABLE access_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fingerprint_id TEXT NOT NULL,
    bssid TEXT NOT NULL,
    rssi INTEGER NOT NULL,
    frequency INTEGER,
    ssid TEXT,
    FOREIGN KEY (fingerprint_id) 
        REFERENCES fingerprints(fingerprint_id) 
        ON DELETE CASCADE
);

-- ایندکس‌ها
CREATE INDEX idx_fingerprint_id ON fingerprints(fingerprint_id);
CREATE INDEX idx_ap_fingerprint_id ON access_points(fingerprint_id);
CREATE INDEX idx_ap_bssid ON access_points(bssid);
```

## نکات طراحی

### 1. Separation of Concerns
- هر ماژول مسئولیت مشخصی دارد
- وابستگی‌ها به حداقل رسیده است

### 2. Error Handling
- تمام خطاها به درستی مدیریت می‌شوند
- پیام‌های خطای واضح به کاربر نمایش داده می‌شود

### 3. Privacy by Design
- MAC address دستگاه هش می‌شود
- اطلاعات حساس به صورت شفاف نمایش داده می‌شود

### 4. Extensibility
- ساختار ماژولار امکان افزودن ویژگی‌های جدید را فراهم می‌کند
- تنظیمات در یک فایل متمرکز شده است

### 5. Testability
- ماژول‌ها به صورت مستقل قابل تست هستند
- Dependency Injection برای تست‌پذیری بهتر

