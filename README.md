# WiFi KNN Locator

A Flutter mobile application for indoor localization using Wi-Fi (RSSI + MAC) and K-Nearest Neighbors (KNN) algorithm.

## Features

- ✅ Wi-Fi–only scanning (BSSID, RSSI, frequency, timestamp) – بدون استفاده از IMU
- ✅ Local fingerprint database + training mode
- ✅ Persistent per-user UUID stored on device (no backend needed)
- ✅ Automatic logging of every Wi-Fi scan & KNN estimate در SQLite
- ✅ Indoor localization via KNN fingerprinting + confidence scoring
- ✅ Movement prediction (Markov chain) based on location history
- ✅ Interactive map: add reference tags by tapping (data captured automatically)
- ✅ Privacy: hashed identifiers, MAC masking, transparency panel
- ✅ CLI-friendly workflow (Flutter SDK + terminal commands only)

## Architecture

### Modular Structure

```
lib/
├── config.dart                 # Configurable parameters
├── data_model.dart             # Data models (scans, fingerprints, history, predictions)
├── wifi_scanner.dart           # Wi-Fi scanning module
├── local_database.dart         # SQLite database management
├── knn_localization.dart       # KNN algorithm implementation
├── main.dart                   # Main UI
├── services/
│   ├── fingerprint_service.dart    # Training/fingerprint workflows
│   ├── data_logger_service.dart    # Logging Wi-Fi scans & location history
│   ├── movement_prediction_service.dart # Markov predictor for next zone
│   ├── location_service.dart
│   └── settings_service.dart
└── utils/
    └── privacy_utils.dart      # Privacy utilities (MAC hashing)
```

## Installation

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Android Studio / Xcode

### Install Dependencies

```bash
flutter pub get
```

### Run / Build only with CLI

```bash
# Run on connected device/emulator
flutter run

# Build release APK / AAB (no Android Studio required)
flutter build apk --release
flutter build appbundle --release
```

اسکریپت‌های آماده نیز در ریشه پروژه هستند (`build_apk_simple.bat`, `build_aab.bat`, ...).

## Usage

### Online Mode (Location Estimation)

1. Click "Scan WiFi" button
2. View results:
   - Estimated location (latitude, longitude)
   - Confidence score
   - List of detected Wi-Fi networks
   - Map display

### Training Mode

1. Enable "Training Mode" switch
2. Stand at a known reference point
3. Click "Scan WiFi"
4. Enter coordinates:
   - Latitude
   - Longitude
   - Zone label (optional)
5. Click "Save Fingerprint"

## Data Flow & Storage

### 1. Wi-Fi Scan Logging

هر بار که اسکن انجام می‌شود:

- جدول `wifi_scans`: `id`, `device_id`, `timestamp`
- جدول `wifi_scan_readings`: `scan_id`, `bssid`, `rssi`, `frequency`, `ssid`

### 2. Fingerprint Database

- جدول `fingerprints`: مختصات/لیبل + شناسه اثرانگشت
- جدول `access_points`: RSSIهای ذخیره‌شده برای هر fingerprint

### 3. Location History & Prediction

- جدول `location_history`: `device_id`, `(x,y)`, `zone_label`, `confidence`, `timestamp`
- سرویس Markov با نگاه به آخرین توالی‌ها، حرکت بعدی را پیش‌بینی می‌کند

تمامی جدول‌ها در `lib/local_database.dart` تعریف شده‌اند و با `sqflite` مدیریت می‌شوند.

## KNN Algorithm (Wi-Fi only)

The algorithm uses Euclidean distance on RSSI vectors:

```
distance = √(Σ(RSSI_observed - RSSI_fingerprint)²)
```

Confidence calculation:

```
confidence = 1 / (1 + averageDistance / 100)
```

### Fingerprint source

اثر انگشت‌ها از فایل JSON/CSV (`assets/wifi_fingerprints.csv`) یا نقاطی که کاربر روی نقشه ذخیره می‌کند خوانده می‌شوند. الگوریتم فقط از Wi-Fi RSSI و MAC استفاده می‌کند؛ هیچ سنسور حرکتی/IMU درگیر نیست.

## Movement Prediction (Markov)

- با استفاده از تاریخچه‌ی `location_history`، گذارهای (zone_i → zone_j) شمرده می‌شوند.
- محتمل‌ترین ناحیه‌ی بعدی و احتمال متناظر بر اساس `count(zone_i → zone_j) / Σ counts` محاسبه می‌شود.
- نتیجه در UI تحت عنوان «پیش‌بینی حرکت بعدی (Markov)» نمایش داده می‌شود.

## Unique User ID & Privacy

- برای هر نصب، یک UUID تولید و در `shared_preferences` ذخیره می‌شود.
- این UUID (در صورت نیاز) هش شده و برای ثبت در پایگاه داده و شناسه دستگاه استفاده می‌شود.
- تمامی MAC/BSSIDها به شکل ماسک‌شده نمایش داده می‌شوند تا شفافیت همراه با حریم خصوصی فراهم شود.

## Privacy

Device MAC address is hashed using SHA-256 before storage or transmission.

## Testing

```bash
flutter test
```

## Configuration

Edit `lib/config.dart` to adjust parameters:

- `defaultK`: Number of neighbors (default: 3)
- `scanInterval`: Scan interval duration
- `confidenceThreshold`: Minimum confidence for display

## License

MIT License

---

For detailed documentation in Persian/Farsi, see [README_FA.md](README_FA.md).
