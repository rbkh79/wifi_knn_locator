import '../data_model.dart';
import '../local_database.dart';

/// مدل ساده Markov برای پیش‌بینی حرکت بعدی کاربر
class MovementPredictionService {
  final LocalDatabase _database;

  MovementPredictionService(this._database);

  Future<MovementPrediction> predictNextZone(String deviceId) async {
    final history = await _database.getLocationHistory(
      deviceId: deviceId,
      limit: 100,
      ascending: true,
    );

    if (history.length < 2) {
      return MovementPrediction(
        predictedZone: null,
        probability: 0,
        generatedAt: DateTime.now(),
      );
    }

    final transitions = <String, Map<String, int>>{};

    for (var i = 0; i < history.length - 1; i++) {
      final current = _normalizeZone(history[i]);
      final next = _normalizeZone(history[i + 1]);
      transitions.putIfAbsent(current, () => {});
      transitions[current]![next] = (transitions[current]![next] ?? 0) + 1;
    }

    final lastZone = _normalizeZone(history.last);
    final nextCounts = transitions[lastZone];
    if (nextCounts == null || nextCounts.isEmpty) {
      return MovementPrediction(
        predictedZone: null,
        probability: 0,
        generatedAt: DateTime.now(),
      );
    }

    String? bestZone;
    int bestCount = 0;
    int total = 0;

    nextCounts.forEach((zone, count) {
      total += count;
      if (count > bestCount) {
        bestCount = count;
        bestZone = zone;
      }
    });

    final double probability = total == 0 ? 0.0 : bestCount / total;

    return MovementPrediction(
      predictedZone: bestZone,
      probability: probability,
      generatedAt: DateTime.now(),
    );
  }

  String _normalizeZone(LocationHistoryEntry entry) {
    if (entry.zoneLabel != null && entry.zoneLabel!.isNotEmpty) {
      return entry.zoneLabel!;
    }

    // اگر لیبل وجود ندارد، از گرید تقریبی بر اساس مختصات استفاده می‌کنیم
    final latBucket = entry.latitude.toStringAsFixed(3);
    final lonBucket = entry.longitude.toStringAsFixed(3);
    return '$latBucket,$lonBucket';
  }
}

