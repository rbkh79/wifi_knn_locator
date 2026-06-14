# WiFi + BTS KNN Locator

A Flutter mobile application for indoor/outdoor localization using Wi-Fi (RSSI + MAC), Cell Tower (BTS), and K-Nearest Neighbors (KNN) algorithm.

## Features

- ✅ Wi-Fi scanning (BSSID, RSSI, frequency, timestamp) – بدون استفاده از IMU
- ✅ Cell Tower (BTS) scanning via native Android TelephonyManager (2G/3G/4G/5G support)
- ✅ Hybrid localization: Wi-Fi + BTS fusion with automatic mode selection
- ✅ Local fingerprint database + training mode for both Wi-Fi and BTS
- ✅ Persistent per-user UUID stored on device (no backend needed)
- ✅ Automatic logging of every Wi-Fi/BTS scan & KNN estimate در SQLite
- ✅ Indoor/outdoor localization via KNN fingerprinting + confidence scoring
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
├── cell_scanner.dart           # Cell Tower (BTS) scanning module
├── bts_service.dart            # BTS service for location estimation
├── local_database.dart         # SQLite database management
├── knn_localization.dart       # KNN algorithm implementation (Hybrid: Wi-Fi + BTS)
├── main.dart                   # Main UI
├── services/
│   ├── fingerprint_service.dart    # Training/fingerprint workflows
│   ├── data_logger_service.dart    # Logging Wi-Fi/BTS scans & location history
│   ├── movement_prediction_service.dart # Markov predictor for next zone
│   ├── location_service.dart
│   └── settings_service.dart
└── utils/
    ├── privacy_utils.dart      # Privacy utilities (MAC hashing)
    └── rssi_filter.dart        # RSSI filtering and noise reduction
```

### Android Native Layer

```
android/app/src/main/kotlin/com/example/wifi_knn_locator/
└── MainActivity.kt             # Native BTS implementation via TelephonyManager
```

## Installation

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Android Studio / Xcode

### Android Permissions

The app requires the following permissions on Android:

- **Location**: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (required for BTS scanning)
- **Phone**: `READ_PHONE_STATE`, `READ_PRECISE_PHONE_STATE`, `READ_BASIC_PHONE_STATE` (required for BTS on Android 13+)
- **WiFi**: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` (for Android 13+)

**Important**: On Android 13+, both Location and Phone permissions are required for BTS scanning. Location service must be enabled.

### Troubleshooting BTS Issues

If BTS (Cell Tower) data is not being detected:

1. **Check Permissions**: Ensure both Location and Phone permissions are granted in app settings
2. **Enable Location**: Location service must be enabled on the device (even for BTS-only scanning)
3. **Check SIM Card**: Ensure a SIM card is inserted and mobile network is active
4. **Disable Airplane Mode**: Airplane mode blocks all cellular communication
5. **Check Logs**: Run `adb logcat | grep BTS_Service` to see native logs
6. **Android 13+**: Ensure `READ_BASIC_PHONE_STATE` permission is granted
7. **MIUI Devices**: Some MIUI versions may have additional restrictions; check battery optimization settings

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

## KNN Algorithm (Hybrid: Wi-Fi + BTS)

The algorithm uses **Weighted Euclidean Distance** on RSSI vectors:

```
distance = √(Σ(w_i × (RSSI_observed - RSSI_fingerprint)²))
```

Where `w_i` is the combined weight based on:
- **Signal Strength**: Stronger RSSI gets higher weight
- **Frequency**: 5GHz gets 1.3x weight, 2.4GHz gets 1.0x weight

### Hybrid Mode Selection

The system automatically selects the best localization mode:
- **Wi-Fi Priority**: If >= 3 APs with RSSI > -80 dBm are detected
- **Hybrid Mode**: Combines Wi-Fi (60%) and BTS (40%) when both are available
- **BTS Only**: When Wi-Fi is weak or unavailable
- **Wi-Fi Only**: When BTS data is unavailable

### Confidence Calculation

Improved confidence scoring based on distance distribution:

```
confidence = 1 - (minDistance / maxExpectedDistance)
```

Where `maxExpectedDistance` is calibrated based on historical data.

### RSSI Filtering

- **Moving Average**: Reduces noise by averaging multiple scans
- **Median Filter**: Robust against outliers
- **Kalman Filter**: Advanced filtering for RSSI time series
- **Temporary AP Removal**: Filters APs that appear in < 30% of scans
- **Hotspot Detection**: Removes mobile hotspots (SSID containing "Android", "Hotspot")
- **Outlier Detection**: Z-score based outlier removal

### Frequency-Based Weighting

2.4GHz and 5GHz bands receive different weights:
- 5GHz: Higher weight (more stable, less interference)
- 2.4GHz: Lower weight (more interference, variable)

### Fingerprint source

اثر انگشت‌ها از فایل JSON/CSV (`assets/wifi_fingerprints.csv`) یا نقاطی که کاربر روی نقشه ذخیره می‌کند خوانده می‌شوند. الگوریتم از Wi-Fi RSSI/MAC و BTS Cell ID/TAC استفاده می‌کند؛ هیچ سنسور حرکتی/IMU درگیر نیست.

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
