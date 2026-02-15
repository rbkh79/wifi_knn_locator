import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data_model.dart';
import '../models/environment_type.dart';
import '../widgets/position_marker.dart';

/// ویجت نقشه تعاملی با flutter_map
class PositionMapWidget extends StatefulWidget {
  final LocationEstimate? currentPosition;
  final EnvironmentType environmentType;
  final List<LocationEstimate>? trajectoryHistory;
  final bool isScanning;
  final VoidCallback? onCenterPressed;
  final ValueChanged<LatLng>? onMapTap;

  const PositionMapWidget({
    Key? key,
    this.currentPosition,
    this.environmentType = EnvironmentType.unknown,
    this.trajectoryHistory,
    this.isScanning = false,
    this.onCenterPressed,
    this.onMapTap,
  }) : super(key: key);

  @override
  State<PositionMapWidget> createState() => _PositionMapWidgetState();
}

class _PositionMapWidgetState extends State<PositionMapWidget>
    with SingleTickerProviderStateMixin {
  late MapController _mapController;
  late AnimationController _radarController;
  LatLng? _mapCenter;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _radarController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // تنظیم موقعیت اولیه
    if (widget.currentPosition != null) {
      _mapCenter = LatLng(
        widget.currentPosition!.latitude,
        widget.currentPosition!.longitude,
      );
    } else {
      _mapCenter = const LatLng(35.6892, 51.3895); // تهران
    }

    if (widget.isScanning) {
      _radarController.repeat();
    }
  }

  @override
  void didUpdateWidget(PositionMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isScanning != widget.isScanning) {
      if (widget.isScanning) {
        _radarController.repeat();
      } else {
        _radarController.stop();
      }
    }

    if (widget.currentPosition != null &&
        oldWidget.currentPosition != widget.currentPosition) {
      _mapCenter = LatLng(
        widget.currentPosition!.latitude,
        widget.currentPosition!.longitude,
      );
      _mapController.move(_mapCenter!, 17);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];

    // نشانگر موقعیت فعلی
    if (widget.currentPosition != null && _mapCenter != null) {
      markers.add(
        Marker(
          point: _mapCenter!,
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // رادار (اگر در حال اسکن باشد)
              if (widget.isScanning)
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, child) {
                    return Container(
                      width: 100 * (0.5 + _radarController.value * 0.5),
                      height: 100 * (0.5 + _radarController.value * 0.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _getMarkerColor().withOpacity(
                            (1 - _radarController.value) * 0.5,
                          ),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              // نشانگر
              PositionMarker(
                environmentType: widget.environmentType,
                confidence: widget.currentPosition!.confidence,
                showConfidenceRing: true,
              ),
            ],
          ),
        ),
      );
    }

    // مسیر حرکت (تاریخچه)
    final polylines = <Polyline>[];
    if (widget.trajectoryHistory != null && widget.trajectoryHistory!.length > 1) {
      final points = widget.trajectoryHistory!
          .map((e) => LatLng(e.latitude, e.longitude))
          .toList();
      polylines.add(
        Polyline(
          points: points,
          color: _getMarkerColor().withOpacity(0.6),
          strokeWidth: 3,
          isoDuration: const Duration(milliseconds: 500),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _mapCenter ?? const LatLng(35.6892, 51.3895),
        initialZoom: 17,
        minZoom: 5,
        maxZoom: 19,
        onTap: (_, latlng) => widget.onMapTap?.call(latlng),
      ),
      children: [
        // تایل نقشه (OpenStreetMap)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.wifi.knn.locator',
          maxNativeZoom: 19,
          tileProvider: NetworkTileProvider(),
        ),

        // خطوط مسیر
        PolylineLayer(polylines: polylines),

        // نشانگرها
        MarkerLayer(markers: markers),

        // کنترل‌های نقشه
        SimpleAttributionWidget(
          source: const Text('© OpenStreetMap contributors'),
        ),
      ],
      nonRotatedLayers: [
        // دکمه مرکزیابی
        Positioned(
          right: 16,
          bottom: 80,
          child: FloatingActionButton(
            mini: true,
            onPressed: () {
              if (_mapCenter != null) {
                _mapController.move(_mapCenter!, 17);
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),

        // مقیاس نقشه
        Positioned(
          left: 16,
          top: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مقیاس نقشه',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Container(
                  width: 50,
                  height: 2,
                  color: Colors.black,
                ),
                const SizedBox(height: 2),
                Text(
                  '~500m',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getMarkerColor() {
    switch (widget.environmentType) {
      case EnvironmentType.indoor:
        return Colors.blue;
      case EnvironmentType.outdoor:
        return Colors.green;
      case EnvironmentType.hybrid:
        return Colors.purple;
      case EnvironmentType.unknown:
      default:
        return Colors.grey;
    }
  }
}
