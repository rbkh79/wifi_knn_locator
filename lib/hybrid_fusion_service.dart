import 'package:latlong2/latlong.dart';

/// ادغام نتایج Wi‑Fi و BTS به یک موقعیت واحد
class HybridFusionService {
  /// وزن‌دهی و میانگین گیری
  ///
  /// [wifi] و [bts] باید در یک زمان گرفته شده باشند.
  static LatLng? fuse({
    required LatLng? wifi,
    required LatLng? bts,
    double wifiWeight = 0.5,
    double btsWeight = 0.5,
  }) {
    if (wifi == null && bts == null) return null;
    if (wifi == null) return bts;
    if (bts == null) return wifi;
    final sum = wifiWeight + btsWeight;
    return LatLng(
      (wifi.latitude * wifiWeight + bts.latitude * btsWeight) / sum,
      (wifi.longitude * wifiWeight + bts.longitude * btsWeight) / sum,
    );
  }
}
