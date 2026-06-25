# WiFi + BTS KNN Locator

[فارسی](README_FA.md) | **English**

A Flutter mobile app for **GPS-free indoor/outdoor/hybrid localization** that estimates geographic position from **Wi-Fi (RSSI + BSSID)** and **Cell Towers (BTS)** using a **K-Nearest Neighbors (KNN)** fingerprinting algorithm. All sensing is radio-based — **no IMU / motion sensors are used** — and all data stays on device.

> `pubspec.yaml` description: *"A Flutter app that estimates geographic location using WiFi BSSIDs and KNN algorithm."*

---

## ✨ Features

### Localization
- **Wi-Fi Fingerprinting + KNN** for indoor positioning (Weighted Euclidean Distance on RSSI vectors)
- **Cell Tower (BTS) scanning** via native Android `TelephonyManager` (2G/3G/4G/5G, serving + neighbor cells)
- **Dual-SIM support** (e.g. Poco X3 Pro) — scans all active SIMs automatically
- **Automatic environment detection**: `Indoor` / `Outdoor` / `Hybrid` / `Unknown`
- **Hybrid fusion**: weighted blend of Wi-Fi and BTS estimates (default 70% Indoor / 30% Outdoor)
- **Adaptive K**, RSSI weighting, frequency-band weighting (5 GHz weighted higher than 2.4 GHz)

### Signal processing
- RSSI noise reduction: moving average, median filter, Kalman filter
- Outlier removal (Z-score), hotspot/AP-occurrence filtering (default `minApOccurrencePercent = 70`)
- **Fingerprint validation** during training (multiple scans + RSSI variance check, default `validationScanCount = 3`)

### Trajectory & prediction
- **Trajectory tracking** with smoothed path display on the map
- **Path prediction**: Markov chain, N-gram, and velocity-based next-position prediction
- **Movement prediction** (next zone) based on location history
- **Path analysis** (distance, time, point-count statistics)
- **Location confidence service**: GPS↔KNN distance check + "new location" warning

### UI / UX
- **Material Design 3** single-page UI (sections: device location, Wi-Fi/BTS scan, map, environment, signal results, path prediction, debug, settings, researcher mode, transparency)
- **Interactive map** (`flutter_map` + OpenStreetMap): tap to add a reference point — Wi-Fi + BTS are captured automatically
- **Indoor mapping** page, **location history** screen, **settings** screen
- Reference points, KNN estimate, user path, GPS marker, trajectory & prediction polylines with legend

### Data & privacy
- **Offline SQLite** database (`wifi_fingerprints.db`, version 5)
- **Per-install UUID** in `shared_preferences`; device identifier hashed with **SHA-256**
- **MAC masking** of BSSIDs in the UI + transparency panel
- **Automatic CSV export** of every scan (Wi-Fi + BTS + GPS + KNN estimate)
- Fingerprint source: on-device training points + `assets/wifi_fingerprints.csv` / `assets/indoor_maps/`
- No backend required (`backendUrl = null`); no raw data leaves the device

---

## 🏗 Architecture

### App structure

```
lib/
├── main.dart                        # Single-page Material 3 UI
├── config.dart                      # AppConfig — all tunable parameters
├── data_model.dart                  # WifiReading, FingerprintEntry, LocationEstimate, ...
├── wifi_scanner.dart                # Wi-Fi scanning module
├── wifi_service.dart
├── cell_scanner.dart                # Cell Tower (BTS) scanning module
├── bts_service.dart                 # BTS location estimation
├── hybrid_fusion_service.dart       # Weighted Wi-Fi + BTS fusion
├── knn_localization.dart            # KNN algorithm (Weighted Euclidean + adaptive K)
├── local_database.dart              # SQLite management
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
│   ├── fingerprint_service.dart           # Save/load fingerprints
│   ├── fingerprint_validator.dart         # Multi-scan validation
│   ├── indoor_localization_service.dart   # Wi-Fi → KNN
│   ├── outdoor_localization_service.dart  # BTS → KNN
│   ├── unified_localization_service.dart  # Auto Indoor/Outdoor/Hybrid selection
│   ├── trajectory_service.dart            # Path tracking + smoothing
│   ├── path_prediction_service.dart       # Markov / N-gram / velocity
│   ├── trajectory_prediction_service.dart
│   ├── prediction_service.dart
│   ├── movement_prediction_service.dart   # Next-zone (Markov)
│   ├── path_analysis_service.dart         # Path statistics
│   ├── location_confidence_service.dart   # GPS↔KNN confidence check
│   ├── research_analytics_service.dart
│   ├── motion_detection_service.dart
│   ├── data_logger_service.dart           # Log scans + estimates
│   ├── data_export_service.dart
│   ├── auto_csv_service.dart              # Automatic CSV export
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
    ├── privacy_utils.dart            # SHA-256 MAC hashing
    ├── rssi_filter.dart              # RSSI filtering / noise reduction
    ├── permission_utils.dart
    └── profiler.dart
```

### Android native layer

```
android/app/src/main/kotlin/com/example/wifi_knn_locator/
└── MainActivity.kt                  # Native BTS scanning via TelephonyManager
```

### Data flow

```
1. Wi-Fi scan + BTS scan (wifi_scanner.dart + cell_scanner.dart)  ── run in parallel
        ↓
2. WifiScanResult + CellScanResult (data_model.dart)
        ↓
3. UnifiedLocalizationService
       ├─ IndoorLocalizationService  (Wi-Fi → KNN)
       └─ OutdoorLocalizationService (BTS → KNN)
        ↓
4. Environment detection  →  Indoor / Outdoor / Hybrid / Unknown
        ↓
5. LocationConfidenceService  (GPS↔KNN distance, reliability, "new location" warning)
        ↓
6. [Training] → save fingerprint (with validation) to SQLite
   [Online]   →
       ├─ show in UI (main.dart)
       ├─ add to TrajectoryService
       ├─ predict next path  (PathPredictionService)
       ├─ predict next zone  (MovementPredictionService)
       ├─ log to DataLoggerService
       └─ AutoCsvService CSV export
```

---

## 🧠 Environment detection (from code)

| Environment | Condition |
|---|---|
| **Indoor** | `accessPointCount >= 3` **AND** `wifiStrength > 0.3`, where `wifiStrength = rssiScore × 0.6 + apCountScore × 0.4` (RSSI from −100→0.0 to −50→1.0) |
| **Outdoor** | At least one reliable cell tower (serving or neighbor) |
| **Hybrid** | Both Indoor and Outdoor are reliable → weighted blend (default 70% Indoor + 30% Outdoor) |
| **Unknown** | Neither reliable → estimate is discarded (not shown) |

---

## 📐 KNN algorithm

**Weighted Euclidean Distance** on RSSI vectors:

```
distance = √( Σ wᵢ · (RSSI_observed − RSSI_fingerprint)² )
```

- `wᵢ` combines **signal strength** (stronger RSSI → higher weight) and **frequency band** (5 GHz ≈ 1.3×, 2.4 GHz = 1.0×)
- Missing BSSID on one side defaults to `−100 dBm`
- K nearest neighbors are averaged with weight `1 / (distance + 1)`
- **Adaptive K** (`minK=1 … maxK=10`, `defaultK=3`, `adaptiveRadiusMeters=4.0`)

**Confidence:**

```
confidence = 1 − (minDistance / maxExpectedDistance)
```

Result is shown only if `confidence ≥ 0.3` (`confidenceThreshold`).

---

## 🚀 Installation

### Prerequisites
- Flutter SDK `>=3.0.0` (Dart `>=3.0.0 <4.0.0`)
- Android Studio / Xcode (or CLI-only)

### Install dependencies

```bash
flutter pub get
```

### Run / Build (CLI-only is fine)

```bash
flutter run                       # run on connected device/emulator
flutter build apk --release       # release APK
flutter build appbundle --release # release AAB
```

Ready-made helper scripts are in the project root: `build_apk_simple.bat`, `build_aab.bat`, `build_apk_smart.bat`, …

---

## 📱 Android permissions

Declared in `android/app/src/main/AndroidManifest.xml`:

- **Location**: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- **Wi-Fi**: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` (Android 13+)
- **Network**: `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE`
- **Phone (for BTS)**: `READ_PHONE_STATE`, `READ_PRECISE_PHONE_STATE`, `READ_BASIC_PHONE_STATE` (Android 13+)
- **Storage**: `READ/WRITE_EXTERNAL_STORAGE` (≤ API 32); `READ_MEDIA_IMAGES/VIDEO/AUDIO` (Android 13+)

> ⚠️ On **Android 13+**, both **Location** and **Phone** permissions are required for BTS scanning, and the device location service must be enabled.

### Troubleshooting BTS

1. Grant both **Location** and **Phone** permissions.
2. Enable the device **Location** service (even for BTS-only mode).
3. Insert an active **SIM** and disable **Airplane mode**.
4. On **MIUI**, set Location to *"Always allow"* and check battery optimization.
5. **Dual-SIM**: the app scans all active SIMs — verify the default SIM in Android settings.
6. Inspect logs: `adb logcat | grep BTS_Service`.

---

## 🧭 Usage

### Online mode (estimate position)
1. Press **"Start Wi-Fi + BTS scan"**.
2. The app scans Wi-Fi + BTS in parallel, runs the unified localization, and shows:
   - Estimated **latitude / longitude** and **zone label**
   - **Environment** (Indoor/Outdoor/Hybrid/Unknown) and **confidence**
   - Detected Wi-Fi networks and BTS list
   - Position on the interactive map, plus trajectory & prediction polylines
   - Reliability warning if confidence is low or you're in a new location

### Training mode (collect fingerprints)
1. Toggle **"Training Mode"**.
2. **Option A** — tap the map to drop a reference point (Wi-Fi + BTS are scanned automatically).
   **Option B** — type latitude / longitude / zone label manually.
3. (Optional) Validation runs multiple scans and checks RSSI variance.
4. Press **"Save fingerprint"** (floating action button).

### Tips for better accuracy
- 10–20 reference points per zone, 2–5 m apart.
- Scan 2–3 times per point; use meaningful labels ("Room 101", "Hallway").

---

## 🗄 Database schema (SQLite)

All tables are defined in `lib/local_database.dart` and managed with `sqflite`.

| Table | Purpose |
|---|---|
| `fingerprints` | Wi-Fi fingerprint metadata (id, fingerprint_id, lat, lon, zone_label, session_id, context_id, device_id, created_at) |
| `access_points` | RSSI/frequency/SSID per fingerprint |
| `cell_fingerprints` | BTS fingerprint metadata |
| `cell_towers` | cell_id, lac, tac, mcc, mnc, signal_strength per fingerprint |
| `wifi_scans` / `wifi_scan_readings` | per-scan Wi-Fi log |
| `raw_scans` / `raw_scan_readings` | raw scan log (session/context aware) |
| `location_history` | logged estimates (+ environment_type) |
| `training_sessions` | session/context bookkeeping |

Indexes: `idx_fingerprint_id`, `idx_ap_fingerprint_id`, `idx_ap_bssid`, `idx_scan_timestamp`.

---

## ⚙️ Configuration

All tunable values live in `lib/config.dart` (`AppConfig`):

```dart
// Scan
static const Duration scanInterval   = Duration(seconds: 5);
static const int minApCountForEvaluation = 3;
static const Duration scanWaitTime   = Duration(seconds: 2);

// KNN
static const int defaultK = 3;            // adaptive K
static const int minK = 1, maxK = 10;
static const bool enableAdaptiveK = true;
static const double adaptiveRadiusMeters = 4.0;
static const int adaptiveNeighborsPerK = 4;

// Database
static const String databaseName = 'wifi_fingerprints.db';
static const int databaseVersion = 5;

// Privacy
static const bool hashDeviceMac = true;
static const bool showFullMacAddresses = false;

// Map
static const double defaultMapZoom = 15.0;
static const double minMapZoom = 5.0, maxMapZoom = 18.0;

// RSSI thresholds (dBm)
static const int excellentRssi = -50, goodRssi = -60,
                 fairRssi = -70,    poorRssi = -80;

// Confidence
static const double confidenceThreshold = 0.3;

// KNN enhancements
static const bool useRssiWeighting  = true;
static const bool useNoiseFiltering = true;
static const int minApOccurrencePercent = 70;
static const int validationScanCount    = 3;
static const double maxRssiVariance = 15.0; // dBm
```

---

## 🔒 Privacy

- A per-install **UUID** is generated and stored in `shared_preferences`.
- The device/MAC identifier is **SHA-256 hashed** before storage or display.
- BSSIDs are shown **masked**; a transparency panel lists what is collected.
- **No backend** is used by default (`backendUrl = null`); all data stays local.

---

## 🧪 Testing

```bash
flutter test                                    # all tests
flutter test test/knn_localization_test.dart    # KNN
flutter test test/wifi_scanner_test.dart        # Wi-Fi scanner
flutter test test/privacy_utils_test.dart       # privacy utils
flutter test test/integration_test.dart         # integration
```

---

## 📄 License

MIT License — see `LICENSE`.

---

For the Persian/Farsi version, see [README_FA.md](README_FA.md).
