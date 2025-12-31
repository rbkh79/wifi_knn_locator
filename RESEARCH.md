# مستندات پژوهشی - WiFi KNN Locator

این مستند برای پژوهشگران و دانشجویانی که از این اپلیکیشن برای پایان‌نامه یا تحقیق استفاده می‌کنند، طراحی شده است.

## 📋 فهرست مطالب

1. [معماری سیستم](#معماری-سیستم)
2. [جمع‌آوری داده‌ها](#جمع‌آوری-داده‌ها)
3. [الگوریتم KNN](#الگوریتم-knn)
4. [معیارهای ارزیابی دقت](#معیارهای-ارزیابی-دقت)
5. [پیش‌بینی حرکت (Markov)](#پیش‌بینی-حرکت-markov)
6. [Export داده‌ها](#export-داده‌ها)
7. [مقایسه با روش‌های دیگر](#مقایسه-با-روش‌های-دیگر)

---

## معماری سیستم

### ساختار داده‌ها

#### 1. Fingerprint (اثرانگشت)
- **مختصات جغرافیایی**: `latitude`, `longitude`
- **لیبل ناحیه**: `zoneLabel` (اختیاری)
- **لیست APها**: هر AP شامل `BSSID`, `RSSI`, `frequency`, `SSID`
- **Timestamp**: زمان ثبت

#### 2. WiFi Scan Log
- **شناسه دستگاه**: UUID هش‌شده
- **Timestamp**: زمان اسکن
- **لیست APها**: با RSSI و فرکانس

#### 3. Location History
- **موقعیت تخمینی**: `latitude`, `longitude`
- **ضریب اطمینان**: `confidence` (0.0 تا 1.0)
- **Timestamp**: زمان تخمین

### پایگاه داده SQLite

#### جداول اصلی:

```sql
-- Fingerprints (نقاط مرجع)
CREATE TABLE fingerprints (
    id INTEGER PRIMARY KEY,
    fingerprint_id TEXT UNIQUE,
    latitude REAL,
    longitude REAL,
    zone_label TEXT,
    created_at TEXT,
    device_id TEXT
);

-- Access Points (برای هر fingerprint)
CREATE TABLE access_points (
    id INTEGER PRIMARY KEY,
    fingerprint_id TEXT,
    bssid TEXT,
    rssi INTEGER,
    frequency INTEGER,
    ssid TEXT
);

-- WiFi Scan Logs
CREATE TABLE wifi_scans (
    id INTEGER PRIMARY KEY,
    device_id TEXT,
    timestamp TEXT
);

-- WiFi Scan Readings
CREATE TABLE wifi_scan_readings (
    id INTEGER PRIMARY KEY,
    scan_id INTEGER,
    bssid TEXT,
    rssi INTEGER,
    frequency INTEGER,
    ssid TEXT
);

-- Location History
CREATE TABLE location_history (
    id INTEGER PRIMARY KEY,
    device_id TEXT,
    latitude REAL,
    longitude REAL,
    zone_label TEXT,
    confidence REAL,
    timestamp TEXT
);
```

---

## جمع‌آوری داده‌ها

### روش 1: Training Mode (دستی)

1. **فعال کردن Training Mode** در بخش "اسکن Wi-Fi"
2. **ایستادن در نقطه مرجع** با مختصات شناخته‌شده
3. **انجام اسکن Wi-Fi**
4. **وارد کردن مختصات** (Latitude, Longitude)
5. **وارد کردن لیبل ناحیه** (اختیاری، مثلاً "اتاق 101")
6. **ذخیره اثرانگشت**

### روش 2: کلیک روی نقشه

1. **باز کردن بخش "نمایش نقشه و نقاط مرجع"**
2. **کلیک روی نقطه مورد نظر** روی نقشه
3. **وارد کردن لیبل ناحیه** (اختیاری)
4. **تأیید** - اسکن Wi-Fi به صورت خودکار انجام می‌شود

### نکات مهم برای جمع‌آوری داده

- **تعداد نقاط مرجع**: حداقل 10-20 نقطه در هر ناحیه
- **فاصله نقاط**: 2-5 متر بین نقاط مرجع
- **تنوع موقعیت**: نقاط را در گوشه‌ها، مرکز، و مسیرها قرار دهید
- **تکرار اسکن**: در هر نقطه 2-3 بار اسکن انجام دهید (اگر Validation فعال باشد)
- **برچسب‌گذاری**: از لیبل‌های معنادار استفاده کنید

---

## الگوریتم KNN

### فرمول ریاضی

#### 1. محاسبه فاصله اقلیدسی وزن‌دار

```
distance = √(Σ (RSSI_observed - RSSI_fingerprint)² × weight)
```

که در آن:
- `weight = f(RSSI)` - وزن بر اساس قدرت RSSI
- برای APهای مشاهده نشده: `RSSI = -100 dBm` (مقدار پیش‌فرض)

#### 2. وزن‌دهی RSSI

```dart
weight = 10^(-RSSI/10) × 0.7 + (1 / RSSI²) × 0.3
```

RSSI قوی‌تر = وزن بیشتر

#### 3. محاسبه موقعیت تخمینی

```
lat_estimated = Σ(lat_i × weight_i) / Σ(weight_i)
lon_estimated = Σ(lon_i × weight_i) / Σ(weight_i)
```

که در آن:
- `i` = همسایه‌های k نزدیک
- `weight_i = 1 / (distance_i + 1)`

#### 4. محاسبه ضریب اطمینان

```
confidence = (normalized_distance × 0.7) + (consistency × 0.3)
```

که در آن:
- `normalized_distance = 1 / (1 + avg_distance / 100)`
- `consistency = 1 / (1 + std_dev / 50)`

### بهبودهای اعمال شده

#### 1. فیلتر نویز (Noise Filtering)
- **میانگین متحرک**: چند اسکن پشت‌سرهم → میانه RSSI
- **حذف APهای موقت**: فقط APهایی که در >70% اسکن‌ها ظاهر شده‌اند

#### 2. وزن‌دهی RSSI
- RSSI قوی‌تر = تأثیر بیشتر در محاسبه فاصله
- استفاده از ترکیب توان و معکوس مربع

#### 3. Validation
- **چند اسکن**: 3 بار اسکن برای هر fingerprint
- **بررسی همگرایی**: واریانس RSSI باید < 15 dBm
- **فیلتر APهای موقت**: حذف APهایی که به ندرت دیده می‌شوند

---

## معیارهای ارزیابی دقت

### 1. خطای مکانی (Positioning Error)

```
error = √((lat_estimated - lat_actual)² + (lon_estimated - lon_actual)²) × 111,000
```

(ضریب 111,000 برای تبدیل درجه به متر)

### 2. ضریب اطمینان (Confidence Score)

- **> 0.7**: اعتماد بالا
- **0.3 - 0.7**: اعتماد متوسط
- **< 0.3**: اعتماد پایین (نتیجه نمایش داده نمی‌شود)

### 3. دقت ناحیه (Zone Accuracy)

```
zone_accuracy = (تعداد_تخمین_های_صحیح / تعداد_کل_تخمین‌ها) × 100%
```

### 4. معیارهای آماری

- **میانگین خطا**: `mean_error`
- **میانه خطا**: `median_error`
- **انحراف معیار**: `std_dev`
- **صدک 95**: `95th_percentile`

### نحوه محاسبه در Python/MATLAB

```python
import pandas as pd
import numpy as np

# بارگذاری داده‌های Export شده
df = pd.read_csv('wifi_knn_data_export.csv')

# فیلتر Location History
location_history = df[df['Type'] == 'Location History']

# محاسبه خطا (نیاز به مختصات واقعی دارد)
# location_history['error'] = ...

mean_error = location_history['error'].mean()
median_error = location_history['error'].median()
std_error = location_history['error'].std()
percentile_95 = location_history['error'].quantile(0.95)
```

---

## پیش‌بینی حرکت (Markov)

### مدل Markov ساده

#### 1. ساخت ماتریس انتقال

```
P(zone_next | zone_current) = count(zone_current → zone_next) / count(zone_current)
```

#### 2. پیش‌بینی

```
predicted_zone = argmax(P(zone_next | zone_current))
probability = max(P(zone_next | zone_current))
```

### محدودیت‌ها

- نیاز به تاریخچه کافی (حداقل 10-20 تخمین موقعیت)
- فقط برای ناحیه‌های با لیبل کار می‌کند
- مدل ساده - برای پیچیده‌تر می‌توان از LSTM یا HMM استفاده کرد

---

## Export داده‌ها

### فرمت CSV

فایل CSV شامل ستون‌های زیر است:

- `Type`: نوع داده (Fingerprint, WiFi Scan, Location History)
- `ID`: شناسه رکورد
- `Timestamp`: زمان
- `Latitude`, `Longitude`: مختصات
- `Zone Label`: لیبل ناحیه
- `BSSID`, `RSSI`, `Frequency`, `SSID`: اطلاعات AP
- `Confidence`: ضریب اطمینان
- `Device ID`: شناسه دستگاه

### فرمت JSON

ساختار JSON شامل سه آرایه:
- `fingerprints`: تمام اثرانگشت‌ها
- `wifi_scans`: تمام اسکن‌های Wi-Fi
- `location_history`: تمام تخمین‌های موقعیت

### محل فایل‌ها

- Android: `/data/data/com.example.wifi_knn_locator_new/app_flutter/`
- یا از طریق `path_provider`: `getApplicationDocumentsDirectory()`

---

## مقایسه با روش‌های دیگر

### KNN vs Weighted KNN

| معیار | KNN خام | KNN با وزن‌دهی RSSI |
|-------|---------|---------------------|
| دقت | پایه | بهبود یافته |
| مقاومت در برابر نویز | کم | متوسط |
| پیچیدگی محاسباتی | O(n) | O(n) |

### KNN vs Gaussian Process

| معیار | KNN | Gaussian Process |
|-------|-----|------------------|
| دقت | متوسط | بالا |
| نیاز به داده | کم | زیاد |
| پیچیدگی | کم | زیاد |
| زمان محاسبه | سریع | کند |

### KNN vs Neural Networks

| معیار | KNN | Neural Networks |
|-------|-----|-----------------|
| نیاز به آموزش | ندارد | دارد |
| نیاز به داده | متوسط | زیاد |
| قابلیت تعمیم | محدود | خوب |
| تفسیرپذیری | بالا | پایین |

---

## نکات پژوهشی

### 1. متغیرهای مستقل (Independent Variables)

- تعداد نقاط مرجع
- فاصله بین نقاط مرجع
- تعداد APهای مشاهده شده
- کیفیت RSSI (میانگین، واریانس)
- استفاده از فیلتر نویز
- استفاده از وزن‌دهی RSSI

### 2. متغیرهای وابسته (Dependent Variables)

- خطای مکانی (متر)
- ضریب اطمینان
- دقت ناحیه (%)

### 3. فرضیه‌های قابل آزمایش

- **H1**: استفاده از وزن‌دهی RSSI دقت را بهبود می‌دهد
- **H2**: فیلتر نویز خطا را کاهش می‌دهد
- **H3**: افزایش تعداد نقاط مرجع دقت را بهبود می‌دهد
- **H4**: Validation کیفیت داده‌ها را بهبود می‌دهد

### 4. تحلیل آماری پیشنهادی

- **t-test**: مقایسه دقت KNN خام vs KNN بهبود یافته
- **ANOVA**: تأثیر تعداد نقاط مرجع بر دقت
- **Correlation**: رابطه بین تعداد AP و دقت
- **Regression**: پیش‌بینی خطا بر اساس متغیرهای مستقل

---

## مثال کد Python برای تحلیل

```python
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats

# بارگذاری داده‌ها
df = pd.read_csv('wifi_knn_data_export.csv')

# فیلتر Location History
locations = df[df['Type'] == 'Location History']

# محاسبه آمار
print(f"تعداد تخمین‌ها: {len(locations)}")
print(f"میانگین Confidence: {locations['Confidence'].mean():.3f}")
print(f"میانه Confidence: {locations['Confidence'].median():.3f}")

# نمودار توزیع Confidence
plt.hist(locations['Confidence'], bins=20)
plt.xlabel('Confidence')
plt.ylabel('Frequency')
plt.title('Distribution of Confidence Scores')
plt.show()

# تحلیل RSSI
wifi_scans = df[df['Type'] == 'WiFi Scan']
print(f"میانگین RSSI: {wifi_scans['RSSI'].mean():.2f} dBm")
print(f"انحراف معیار RSSI: {wifi_scans['RSSI'].std():.2f} dBm")
```

---

## منابع و مراجع

1. **KNN برای Indoor Localization**:
   - Bahl, P., & Padmanabhan, V. N. (2000). RADAR: An in-building RF-based user location and tracking system.

2. **WiFi Fingerprinting**:
   - Youssef, M., & Agrawala, A. (2005). The Horus WLAN location determination system.

3. **Markov Models برای Trajectory Prediction**:
   - Ashbrook, D., & Starner, T. (2003). Using GPS to learn significant locations and predict movement.

---

## پشتیبانی

برای سوالات یا مشکلات:
- بررسی کد در `lib/`
- اجرای تست‌ها: `flutter test`
- بررسی لاگ‌ها در Debug Console

---

**نکته**: این مستند به‌صورت مداوم به‌روزرسانی می‌شود. برای آخرین نسخه، به repository مراجعه کنید.










