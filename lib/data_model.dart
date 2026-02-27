/// مدل‌های داده برای اپلیکیشن

import 'config.dart';

/// خواندن Wi-Fi (نقطه دسترسی مشاهده شده)
class WifiReading {
  final String bssid; // MAC address (BSSID)
  final int rssi; // قدرت سیگنال
  final int? frequency; // فرکانس (MHz) - اختیاری
  final String? ssid; // نام شبکه - اختیاری

  WifiReading({
    required this.bssid,
    required this.rssi,
    this.frequency,
    this.ssid,
  });

  Map<String, dynamic> toMap() {
    return {
      'bssid': bssid,
      'rssi': rssi,
      'frequency': frequency,
      'ssid': ssid,
    };
  }

  factory WifiReading.fromMap(Map<String, dynamic> map) {
    return WifiReading(
      bssid: map['bssid'] as String,
      rssi: map['rssi'] as int,
      frequency: map['frequency'] as int?,
      ssid: map['ssid'] as String?,
    );
  }

  @override
  String toString() => 'WifiReading(bssid: $bssid, rssi: $rssi, freq: $frequency)';
}

/// اسکن کامل Wi-Fi (شامل چندین WifiReading)
class WifiScanResult {
  final String deviceId; // شناسه هش‌شده دستگاه
  final DateTime timestamp;
  final List<WifiReading> accessPoints;

  WifiScanResult({
    required this.deviceId,
    required this.timestamp,
    required this.accessPoints,
  });

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'access_points': accessPoints.map((ap) => ap.toMap()).toList(),
    };
  }

  factory WifiScanResult.fromMap(Map<String, dynamic> map) {
    return WifiScanResult(
      deviceId: map['device_id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      accessPoints: (map['access_points'] as List)
          .map((ap) => WifiReading.fromMap(ap as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// ورودی اثرانگشت (Fingerprint Entry) در پایگاه داده
class FingerprintEntry {
  final int? id; // شناسه در پایگاه داده (null برای ورودی جدید)
  final String fingerprintId; // شناسه یکتا اثرانگشت
  final double latitude;
  final double longitude;
  final String? zoneLabel; // لیبل ناحیه (اختیاری)
  final String? sessionId; // شناسه مسیر/جلسه
  final String? contextId; // شناسه محیط (مثلاً دانشگاه)
  final List<WifiReading> accessPoints;
  final DateTime createdAt;
  final String? deviceId; // شناسه دستگاه که این اثرانگشت را ثبت کرده

  FingerprintEntry({
    this.id,
    required this.fingerprintId,
    required this.latitude,
    required this.longitude,
    this.zoneLabel,
    this.sessionId,
    this.contextId,
    required this.accessPoints,
    required this.createdAt,
    this.deviceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fingerprint_id': fingerprintId,
      'latitude': latitude,
      'longitude': longitude,
      'zone_label': zoneLabel,
      'session_id': sessionId,
      'context_id': contextId,
      'access_points': accessPoints.map((ap) => ap.toMap()).toList(),
      'created_at': createdAt.toIso8601String(),
      'device_id': deviceId,
    };
  }

  factory FingerprintEntry.fromMap(Map<String, dynamic> map) {
    return FingerprintEntry(
      id: map['id'] as int?,
      fingerprintId: map['fingerprint_id'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      zoneLabel: map['zone_label'] as String?,
      sessionId: map['session_id'] as String?,
      contextId: map['context_id'] as String?,
      accessPoints: (map['access_points'] as List)
          .map((ap) => WifiReading.fromMap(ap as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
      deviceId: map['device_id'] as String?,
    );
  }

  /// تبدیل به فرمت قدیمی برای سازگاری با CSV
  Map<String, dynamic> toLegacyMap() {
    final map = <String, dynamic>{
      'lat': latitude,
      'lon': longitude,
    };
    for (final ap in accessPoints) {
      map[ap.bssid] = ap.rssi;
    }
    return map;
  }
}

/// اطلاعات یک جلسه/مسیر آموزش
class TrainingSession {
  final String sessionId;
  final String? contextId;
  final DateTime startedAt;
  final DateTime? finishedAt;

  TrainingSession({
    required this.sessionId,
    this.contextId,
    required this.startedAt,
    this.finishedAt,
  });
}

/// تخمین موقعیت (Location Estimate)
class LocationEstimate {
  final double latitude;
  final double longitude;
  final double confidence; // ضریب اطمینان (0.0 تا 1.0)
  final String? zoneLabel; // لیبل ناحیه تخمینی
  final List<FingerprintEntry> nearestNeighbors; // k همسایه نزدیک
  final double averageDistance; // میانگین فاصله تا همسایه‌ها

  LocationEstimate({
    required this.latitude,
    required this.longitude,
    required this.confidence,
    this.zoneLabel,
    required this.nearestNeighbors,
    required this.averageDistance,
  });

  bool get isReliable => confidence >= AppConfig.confidenceThreshold;

  @override
  String toString() =>
      'LocationEstimate(lat: $latitude, lon: $longitude, confidence: ${confidence.toStringAsFixed(2)})';
}

/// لاگ خام اسکن Wi-Fi (بدون وابستگی به موقعیت)
class RawWifiScan {
  final int? id;
  final String deviceId;
  final DateTime timestamp;
  final String? sessionId;
  final String? contextId;
  final List<WifiReading> readings;

  RawWifiScan({
    this.id,
    required this.deviceId,
    required this.timestamp,
    required this.readings,
    this.sessionId,
    this.contextId,
  });
}

/// رکورد فاصله برای KNN
class DistanceRecord {
  final double distance;
  final FingerprintEntry fingerprint;
  final int index;

  DistanceRecord({
    required this.distance,
    required this.fingerprint,
    required this.index,
  });
}

/// لاگ اسکن Wi-Fi (برای ذخیره‌سازی تاریخچه)
class WifiScanLog {
  final int? id;
  final String deviceId;
  final DateTime timestamp;
  final List<WifiScanLogEntry> readings;

  WifiScanLog({
    this.id,
    required this.deviceId,
    required this.timestamp,
    required this.readings,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'readings': readings.map((r) => r.toMap()).toList(),
    };
  }
}

class WifiScanLogEntry {
  final int? id;
  final String bssid;
  final int rssi;
  final int? frequency;
  final String? ssid;

  WifiScanLogEntry({
    this.id,
    required this.bssid,
    required this.rssi,
    this.frequency,
    this.ssid,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bssid': bssid,
      'rssi': rssi,
      'frequency': frequency,
      'ssid': ssid,
    };
  }
}

/// تاریخچه موقعیت برای هر کاربر
class LocationHistoryEntry {
  final int? id;
  final String deviceId;
  final double latitude;
  final double longitude;
  final String? zoneLabel;
  final double confidence;
  final DateTime timestamp;

  LocationHistoryEntry({
    this.id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    this.zoneLabel,
    required this.confidence,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'zone_label': zoneLabel,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// خروجی پیش‌بینی حرکت (Markov)
class MovementPrediction {
  final String? predictedZone;
  final double probability;
  final DateTime generatedAt;

  MovementPrediction({
    required this.predictedZone,
    required this.probability,
    required this.generatedAt,
  });

  bool get hasPrediction => predictedZone != null && probability > 0;
}

/// اطلاعات یک دکل مخابراتی (Cell Tower)
class CellTowerInfo {
  final int? cellId; // Cell ID
  final int? lac; // Location Area Code (2G/3G)
  final int? tac; // Tracking Area Code (4G/5G)
  final int? mcc; // Mobile Country Code
  final int? mnc; // Mobile Network Code
  final int? signalStrength; // قدرت سیگنال (dBm)
  final String? networkType; // نوع شبکه (GSM, WCDMA, LTE, NR)
  final int? psc; // Primary Scrambling Code (3G)
  final int? pci; // Physical Cell ID (4G/5G)

  CellTowerInfo({
    this.cellId,
    this.lac,
    this.tac,
    this.mcc,
    this.mnc,
    this.signalStrength,
    this.networkType,
    this.psc,
    this.pci,
  });

  Map<String, dynamic> toMap() {
    return {
      'cell_id': cellId,
      'lac': lac,
      'tac': tac,
      'mcc': mcc,
      'mnc': mnc,
      'signal_strength': signalStrength,
      'network_type': networkType,
      'psc': psc,
      'pci': pci,
    };
  }

  factory CellTowerInfo.fromMap(Map<String, dynamic> map) {
    return CellTowerInfo(
      cellId: map['cell_id'] as int?,
      lac: map['lac'] as int?,
      tac: map['tac'] as int?,
      mcc: map['mcc'] as int?,
      mnc: map['mnc'] as int?,
      signalStrength: map['signal_strength'] as int?,
      networkType: map['network_type'] as String?,
      psc: map['psc'] as int?,
      pci: map['pci'] as int?,
    );
  }

  /// تولید شناسه یکتا برای دکل
  String get uniqueId {
    final parts = <String>[];
    if (mcc != null) parts.add('MCC:$mcc');
    if (mnc != null) parts.add('MNC:$mnc');
    if (lac != null) parts.add('LAC:$lac');
    if (tac != null) parts.add('TAC:$tac');
    if (cellId != null) parts.add('CID:$cellId');
    if (psc != null) parts.add('PSC:$psc');
    if (pci != null) parts.add('PCI:$pci');
    return parts.join('|');
  }

  @override
  String toString() => 'CellTowerInfo($uniqueId, signal: $signalStrength)';
}

/// اسکن کامل دکل‌های مخابراتی (شامل دکل متصل و همسایه‌ها)
class CellScanResult {
  final String deviceId;
  final DateTime timestamp;
  final CellTowerInfo? servingCell; // دکل متصل
  final List<CellTowerInfo> neighboringCells; // دکل‌های همسایه

  CellScanResult({
    required this.deviceId,
    required this.timestamp,
    this.servingCell,
    required this.neighboringCells,
  });

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'serving_cell': servingCell?.toMap(),
      'neighboring_cells': neighboringCells.map((cell) => cell.toMap()).toList(),
    };
  }

  factory CellScanResult.fromMap(Map<String, dynamic> map) {
    return CellScanResult(
      deviceId: map['device_id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      servingCell: map['serving_cell'] != null
          ? CellTowerInfo.fromMap(map['serving_cell'] as Map<String, dynamic>)
          : null,
      neighboringCells: (map['neighboring_cells'] as List)
          .map((cell) => CellTowerInfo.fromMap(cell as Map<String, dynamic>))
          .toList(),
    );
  }

  /// دریافت تمام دکل‌ها (متصل + همسایه)
  List<CellTowerInfo> get allCells {
    final cells = <CellTowerInfo>[];
    if (servingCell != null) cells.add(servingCell!);
    cells.addAll(neighboringCells);
    return cells;
  }
}

/// ورودی اثرانگشت سلولی (Cell Fingerprint Entry) در پایگاه داده
class CellFingerprintEntry {
  final int? id;
  final String fingerprintId;
  final double latitude;
  final double longitude;
  final String? zoneLabel;
  final String? sessionId;
  final String? contextId;
  final List<CellTowerInfo> cellTowers;
  final DateTime createdAt;
  final String? deviceId;

  CellFingerprintEntry({
    this.id,
    required this.fingerprintId,
    required this.latitude,
    required this.longitude,
    this.zoneLabel,
    this.sessionId,
    this.contextId,
    required this.cellTowers,
    required this.createdAt,
    this.deviceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fingerprint_id': fingerprintId,
      'latitude': latitude,
      'longitude': longitude,
      'zone_label': zoneLabel,
      'session_id': sessionId,
      'context_id': contextId,
      'cell_towers': cellTowers.map((cell) => cell.toMap()).toList(),
      'created_at': createdAt.toIso8601String(),
      'device_id': deviceId,
    };
  }

  factory CellFingerprintEntry.fromMap(Map<String, dynamic> map) {
    return CellFingerprintEntry(
      id: map['id'] as int?,
      fingerprintId: map['fingerprint_id'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      zoneLabel: map['zone_label'] as String?,
      sessionId: map['session_id'] as String?,
      contextId: map['context_id'] as String?,
      cellTowers: (map['cell_towers'] as List)
          .map((cell) => CellTowerInfo.fromMap(cell as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
      deviceId: map['device_id'] as String?,
    );
  }
}

/// اثرانگشت ترکیبی (Hybrid Fingerprint) شامل Wi-Fi و Cell
class HybridFingerprintEntry {
  final int? id;
  final String fingerprintId;
  final double latitude;
  final double longitude;
  final String? zoneLabel;
  final String? sessionId;
  final String? contextId;
  final List<WifiReading>? accessPoints; // Wi-Fi APs (اختیاری)
  final List<CellTowerInfo>? cellTowers; // Cell Towers (اختیاری)
  final DateTime createdAt;
  final String? deviceId;

  HybridFingerprintEntry({
    this.id,
    required this.fingerprintId,
    required this.latitude,
    required this.longitude,
    this.zoneLabel,
    this.sessionId,
    this.contextId,
    this.accessPoints,
    this.cellTowers,
    required this.createdAt,
    this.deviceId,
  });

  /// بررسی اینکه آیا اثرانگشت Wi-Fi دارد
  bool get hasWifi => accessPoints != null && accessPoints!.isNotEmpty;

  /// بررسی اینکه آیا اثرانگشت Cell دارد
  bool get hasCell => cellTowers != null && cellTowers!.isNotEmpty;

  /// بررسی اینکه آیا اثرانگشت ترکیبی است
  bool get isHybrid => hasWifi && hasCell;
}

