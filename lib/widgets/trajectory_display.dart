/// ویجت نمایش مسیر حرکت (Trajectory Display)
/// 
/// این ویجت مسیر حرکت کاربر را روی نقشه نمایش می‌دهد.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/trajectory_service.dart';

/// ویجت نمایش مسیر حرکت
class TrajectoryDisplay {
  /// ساخت Polyline برای نمایش مسیر روی نقشه
  static Polyline buildTrajectoryPolyline(
    List<TrajectoryPoint> trajectory, {
    Color? color,
    double strokeWidth = 3.0,
  }) {
    if (trajectory.isEmpty) {
      return Polyline(
        points: [],
        strokeWidth: strokeWidth,
        color: color ?? Colors.blue,
      );
    }

    final points = trajectory
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    return Polyline(
      points: points,
      strokeWidth: strokeWidth,
      color: color ?? Colors.blue,
    );
  }

  /// ساخت Marker برای نقاط مسیر
  static List<Marker> buildTrajectoryMarkers(
    List<TrajectoryPoint> trajectory, {
    bool showAll = false,
    int maxMarkers = 10,
  }) {
    if (trajectory.isEmpty) return [];

    final markers = <Marker>[];
    final step = trajectory.length > maxMarkers
        ? (trajectory.length / maxMarkers).ceil()
        : 1;

    for (int i = 0; i < trajectory.length; i += step) {
      final point = trajectory[i];
      markers.add(
        Marker(
          point: LatLng(point.latitude, point.longitude),
          width: 8,
          height: 8,
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: _getColorForEnvironment(point.environmentType),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
          anchorPos: AnchorPos.exactly(Anchor(4, 4)),
        ),
      );
    }

    return markers;
  }

  static Color _getColorForEnvironment(String environmentType) {
    switch (environmentType) {
      case 'indoor':
        return Colors.blue;
      case 'outdoor':
        return Colors.green;
      case 'hybrid':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

