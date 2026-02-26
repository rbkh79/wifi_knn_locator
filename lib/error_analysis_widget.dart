import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// ویجتی که خطاهای BTS/WiFi/Hybrid را نسبت به GPS نمایش می‌دهد
class ErrorAnalysisWidget extends StatelessWidget {
  final LatLng? gps;
  final LatLng? bts;
  final LatLng? wifi;
  final LatLng? hybrid;

  const ErrorAnalysisWidget({
    Key? key,
    this.gps,
    this.bts,
    this.wifi,
    this.hybrid,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (gps == null) {
      return const Text('GPS فعال نیست');
    }
    final btsError = _distance(gps!, bts);
    final wifiError = _distance(gps!, wifi);
    final hybridError = _distance(gps!, hybrid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('خطای BTS نسبت به GPS: ${btsError?.toStringAsFixed(1) ?? '-'} متر'),
        Text('خطای WiFi نسبت به GPS: ${wifiError?.toStringAsFixed(1) ?? '-'} متر'),
        Text('خطای ترکیبی نسبت به GPS: ${hybridError?.toStringAsFixed(1) ?? '-'} متر'),
      ],
    );
  }

  double? _distance(LatLng a, LatLng? b) {
    if (b == null) return null;
    const Distance d = Distance();
    return d.as(LengthUnit.Meter, a, b);
  }
}
