import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../local_database.dart';
import '../data_model.dart';

/// PredictionService
///
/// Scaffolds a Temporal Graph Neural Network (TGNN/TGAT) inference pipeline
/// using a MethodChannel to call native PyTorch inference (e.g. via flutter_torch).
/// If the native model call fails or is not available, a robust heuristic
/// extrapolation fallback is used so the app can still provide path guesses
/// during short Wi‑Fi outages.
class PredictionService {
  final LocalDatabase _database;
  final MethodChannel _torchChannel = const MethodChannel('flutter_torch');

  PredictionService(this._database);

  /// Predicts a short path during a Wi‑Fi outage.
  ///
  /// - `deviceId` is used to fetch recent historical scans and location history.
  /// - `steps` is how many future positions to predict (e.g. 3–10).
  ///
  /// Returns a list of `LocationEstimate` objects (length == steps).
  Future<List<LocationEstimate>> predictDuringOutage({
    required String deviceId,
    int steps = 3,
  }) async {
    // Fetch recent scans and recent location history
    final recentScans = await _database.getRecentWifiScanLogs(deviceId: deviceId, limit: 50);
    final recentLocations = await _database.getLocationHistory(deviceId: deviceId, limit: 20, ascending: false);

    // Build a compact graph representation from recentScans
    final graphPayload = _buildGraphPayload(recentScans);

    // Try calling a native TGNN model via MethodChannel. The native side should
    // expose a method like 'run_tgnn_inference' which accepts the graph payload
    // and returns ordered predicted coordinates.
    try {
      final result = await _torchChannel.invokeMethod('run_tgnn_inference', {
        'graph': graphPayload,
        'steps': steps,
      });

      if (result is Map && result['predictions'] is List) {
        final preds = result['predictions'] as List;
        return preds.map<LocationEstimate>((p) {
          final lat = (p['lat'] as num).toDouble();
          final lon = (p['lon'] as num).toDouble();
          final conf = (p['confidence'] as num?)?.toDouble() ?? 0.3;
          return LocationEstimate(
            latitude: lat,
            longitude: lon,
            confidence: conf,
            zoneLabel: p['zone'] as String?,
            nearestNeighbors: const [],
            averageDistance: 999.0,
          );
        }).toList();
      }
    } catch (e) {
      // If the native inference fails (no plugin, missing model, etc.), fall back
      // to a heuristic extrapolation using recent location history.
    }

    // Heuristic fallback: extrapolate using last velocity vector from location history
    if (recentLocations.length >= 2) {
      final l0 = recentLocations[0];
      final l1 = recentLocations.length > 1 ? recentLocations[1] : l0;

      final dt = l0.timestamp.difference(l1.timestamp).inMilliseconds / 1000.0;
      double vx = 0.0, vy = 0.0;
      if (dt > 0) {
        vx = (l0.latitude - l1.latitude) / dt;
        vy = (l0.longitude - l1.longitude) / dt;
      }

      final predictions = <LocationEstimate>[];
      var baseLat = l0.latitude;
      var baseLon = l0.longitude;
      var decay = 1.0;
      for (int i = 1; i <= steps; i++) {
        // simple linear extrapolation with exponential decay to reflect uncertainty
        baseLat += vx * dt; // step forward by same dt
        baseLon += vy * dt;
        decay *= 0.7; // increase uncertainty with each step

        predictions.add(LocationEstimate(
          latitude: baseLat,
          longitude: baseLon,
          confidence: (l0.confidence * decay).clamp(0.05, 0.8),
          zoneLabel: l0.zoneLabel,
          nearestNeighbors: const [],
          averageDistance: 999.0,
        ));
      }

      return predictions;
    }

    // Last resort: repeat last known location with very low confidence
    if (recentLocations.isNotEmpty) {
      final last = recentLocations.first;
      return List.generate(steps, (i) => LocationEstimate(
            latitude: last.latitude,
            longitude: last.longitude,
            confidence: (last.confidence * math.pow(0.6, i + 1)).clamp(0.01, 0.6),
            zoneLabel: last.zoneLabel,
            nearestNeighbors: const [],
            averageDistance: 999.0,
          ));
    }

    // No history: return empty list
    return <LocationEstimate>[];
  }

  /// Converts recent scans into a compact payload for the native TGNN model.
  /// The payload includes nodes (unique BSSIDs), temporal sequences of RSSI,
  /// and simple co-occurrence edge statistics.
  Map<String, dynamic> _buildGraphPayload(List<WifiScanLog> scans) {
    final nodeIndex = <String, int>{};
    final sequences = <List<int>>[]; // sequences of node indices per scan (ordered by time)
    final rssiSequences = <List<int>>[]; // corresponding RSSI sequences

    for (final scan in scans.reversed) {
      final nodes = <int>[];
      final rssis = <int>[];
      for (final r in scan.readings) {
        final b = r.bssid;
        if (!nodeIndex.containsKey(b)) nodeIndex[b] = nodeIndex.length;
        nodes.add(nodeIndex[b]!);
        rssis.add(r.rssi);
      }
      if (nodes.isNotEmpty) {
        sequences.add(nodes);
        rssiSequences.add(rssis);
      }
    }

    // Build simple co-occurrence edges (count of times two nodes appeared together)
    final edgeWeights = <String, int>{};
    for (final seq in sequences) {
      for (int i = 0; i < seq.length; i++) {
        for (int j = i + 1; j < seq.length; j++) {
          final a = seq[i];
          final b = seq[j];
          final key = a < b ? '\$a-\$b' : '\$b-\$a';
          edgeWeights[key] = (edgeWeights[key] ?? 0) + 1;
        }
      }
    }

    return {
      'node_count': nodeIndex.length,
      'node_map': nodeIndex,
      'sequences': sequences,
      'rssi_sequences': rssiSequences,
      'edges': edgeWeights,
    };
  }
}
