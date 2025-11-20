import '../data_model.dart';
import '../local_database.dart';

/// سرویس مسئول ثبت تاریخچه اسکن‌ها و موقعیت‌ها
class DataLoggerService {
  final LocalDatabase _database;

  DataLoggerService(this._database);

  Future<void> logWifiScan(WifiScanResult scanResult) async {
    final log = WifiScanLog(
      deviceId: scanResult.deviceId,
      timestamp: scanResult.timestamp,
      readings: scanResult.accessPoints
          .map(
            (ap) => WifiScanLogEntry(
              bssid: ap.bssid,
              rssi: ap.rssi,
              frequency: ap.frequency,
              ssid: ap.ssid,
            ),
          )
          .toList(),
    );

    await _database.insertWifiScanLog(log);
  }

  Future<void> logLocationEstimate({
    required String deviceId,
    required LocationEstimate estimate,
  }) async {
    final entry = LocationHistoryEntry(
      deviceId: deviceId,
      latitude: estimate.latitude,
      longitude: estimate.longitude,
      zoneLabel: estimate.zoneLabel,
      confidence: estimate.confidence,
      timestamp: DateTime.now(),
    );

    await _database.insertLocationHistory(entry);
  }
}


