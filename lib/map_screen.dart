import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// صفحه نقشه که چهار نشانگر مجزا را نمایش می‌دهد
class MapScreen extends StatelessWidget {
  final LatLng? gpsPosition;
  final LatLng? btsPosition;
  final LatLng? wifiPosition;
  final LatLng? hybridPosition;
  final VoidCallback? onTap;

  const MapScreen({
    Key? key,
    this.gpsPosition,
    this.btsPosition,
    this.wifiPosition,
    this.hybridPosition,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    void addMarker(LatLng? pos, Color color, String label) {
      if (pos == null) return;
      markers.add(Marker(
        point: pos,
        width: 40,
        height: 40,
        builder: (_) => Icon(Icons.location_on, color: color, size: 36),
      ));
    }

    addMarker(gpsPosition, Colors.purple, 'موقعیت GPS');
    addMarker(btsPosition, Colors.green, 'موقعیت مبتنی بر BTS');
    addMarker(hybridPosition, Colors.blue, 'موقعیت ترکیبی WiFi + BTS');
    addMarker(wifiPosition, Colors.orange, 'موقعیت اثر انگشت WiFi');

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(onTap: (p, latlng) => onTap?.call()),
          layers: [
            TileLayerOptions(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.localization',
            ),
            MarkerLayerOptions(markers: markers),
          ],
        ),
        Positioned(
          top: 8,
          right: 8,
          child: _LegendCard(),
        ),
      ],
    );
  }
}

class _LegendCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _LegendItem(color: Colors.purple, text: 'موقعیت GPS'),
            _LegendItem(color: Colors.green, text: 'موقعیت مبتنی بر BTS'),
            _LegendItem(color: Colors.blue, text: 'موقعیت ترکیبی WiFi + BTS'),
            _LegendItem(color: Colors.orange, text: 'موقعیت اثر انگشت WiFi'),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendItem({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12)),
      ],
    );
  }
}
