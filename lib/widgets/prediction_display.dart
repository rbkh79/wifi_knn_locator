/// ویجت نمایش پیش‌بینی مسیر (Prediction Display)
/// 
/// این ویجت پیش‌بینی مسیر آینده کاربر را نمایش می‌دهد.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/path_prediction_service.dart';

/// ویجت نمایش پیش‌بینی مسیر
class PredictionDisplay {
  /// ساخت Polyline برای نمایش مسیر پیش‌بینی شده
  static Polyline buildPredictionPolyline(
    PathPredictionResult prediction, {
    Color? color,
    double strokeWidth = 2.0,
    bool isDashed = true,
  }) {
    if (prediction.predictedLocations.isEmpty) {
      return Polyline(
        points: [],
        strokeWidth: strokeWidth,
        color: color ?? Colors.orange,
      );
    }

    final points = prediction.predictedLocations
        .map((loc) => LatLng(loc.latitude, loc.longitude))
        .toList();

    // در flutter_map 7.0.2، pattern به صورت مستقیم پشتیبانی نمی‌شود
    // برای خط چین، می‌توان از borderStrokeWidth استفاده کرد
    return Polyline(
      points: points,
      strokeWidth: strokeWidth,
      color: color ?? Colors.orange,
      // pattern برای خط چین در نسخه 7.0.2 به صورت مستقیم پشتیبانی نمی‌شود
    );
  }

  /// ساخت Marker برای نقاط پیش‌بینی شده
  static List<Marker> buildPredictionMarkers(
    PathPredictionResult prediction,
  ) {
    if (prediction.predictedLocations.isEmpty) return [];

    final markers = <Marker>[];
    for (final entry in prediction.predictedLocations.asMap().entries) {
      final index = entry.key;
      final location = entry.value;

      markers.add(
        Marker(
          point: LatLng(location.latitude, location.longitude),
          width: 12,
          height: 12,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.7),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// ساخت ویجت اطلاعات پیش‌بینی
  static Widget buildPredictionInfo(PathPredictionResult prediction) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'پیش‌بینی مسیر',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'روش: ${prediction.predictionMethod}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'تعداد گام‌ها: ${prediction.predictedLocations.length}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'ضریب اطمینان: ${(prediction.overallConfidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12),
          ),
          if (prediction.predictedZone != null)
            Text(
              'ناحیه پیش‌بینی شده: ${prediction.predictedZone}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}

