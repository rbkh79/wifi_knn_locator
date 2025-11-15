# WiFi KNN Locator

A Flutter mobile application for indoor localization using Wi-Fi (RSSI + MAC) and K-Nearest Neighbors (KNN) algorithm.

## Features

- ✅ Periodic Wi-Fi Access Point scanning
- ✅ Complete data recording: MAC (BSSID), RSSI, frequency, SSID
- ✅ Device MAC hashing for privacy protection
- ✅ Offline SQLite database for fingerprint storage
- ✅ KNN algorithm for location estimation
- ✅ Confidence score display
- ✅ Training mode for data collection
- ✅ User-friendly and transparent UI
- ✅ Privacy transparency
- ✅ Unit tests for core modules

## Architecture

### Modular Structure

```
lib/
├── config.dart                 # Configurable parameters
├── data_model.dart             # Data models (WifiReading, FingerprintEntry, LocationEstimate)
├── wifi_scanner.dart           # Wi-Fi scanning module
├── local_database.dart         # SQLite database management
├── knn_localization.dart       # KNN algorithm implementation
├── main.dart                   # Main UI
├── services/
│   └── fingerprint_service.dart # Fingerprint management service
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

### Run Application

```bash
flutter run
```

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

## KNN Algorithm

The algorithm uses Euclidean distance:

```
distance = √(Σ(RSSI_observed - RSSI_fingerprint)²)
```

Confidence calculation:

```
confidence = 1 / (1 + averageDistance / 100)
```

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
