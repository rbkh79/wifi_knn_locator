/// سرویس پیش‌بینی مسیر حرکت (Path Prediction Service)
/// 
/// این سرویس برای پیش‌بینی مسیر کوتاه‌مدت آینده کاربر طراحی شده است.
/// 
/// روش‌های پیش‌بینی:
/// 1. مدل انتقال مارکوف (Markov Chain Model) بین نواحی/سلول‌ها
/// 2. پیش‌بینی مبتنی بر آخرین N حرکت کاربر (N-gram based)
/// 3. پیش‌بینی مبتنی بر سرعت و جهت (Velocity-based)
/// 
/// چرا GPS-Free؟
/// - تمام پیش‌بینی‌ها بر اساس تاریخچه موقعیت‌های GPS-Free است
/// - از Wi-Fi یا Cell-based localization استفاده می‌کند
/// - هیچ وابستگی به سرویس‌های خارجی ندارد
/// 
/// محدودیت‌ها:
/// - پیش‌بینی کوتاه‌مدت است (چند ثانیه تا چند دقیقه)
/// - دقت به کیفیت تاریخچه بستگی دارد
/// - در محیط‌های جدید یا الگوهای غیرمعمول، دقت کاهش می‌یابد
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import 'trajectory_service.dart';

/// نتیجه پیش‌بینی مسیر
class PathPredictionResult {
  final List<PredictedLocation> predictedLocations;
  final double overallConfidence; // ضریب اطمینان کلی
  final String? predictedZone; // ناحیه پیش‌بینی شده
  final String predictionMethod; // روش پیش‌بینی استفاده شده

  PathPredictionResult({
    required this.predictedLocations,
    required this.overallConfidence,
    this.predictedZone,
    required this.predictionMethod,
  });
}

/// موقعیت پیش‌بینی شده
class PredictedLocation {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double confidence;
  final String? zoneLabel;

  PredictedLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.confidence,
    this.zoneLabel,
  });
}

/// سرویس پیش‌بینی مسیر
class PathPredictionService {
  final LocalDatabase _database;
  final TrajectoryService _trajectoryService;

  PathPredictionService(this._database)
      : _trajectoryService = TrajectoryService(_database);

  /// پیش‌بینی مسیر آینده با استفاده از مدل مارکوف
  /// 
  /// این متد از مدل انتقال مارکوف برای پیش‌بینی ناحیه بعدی استفاده می‌کند.
  /// 
  /// [deviceId]: شناسه دستگاه
  /// [steps]: تعداد گام‌های آینده (پیش‌فرض: 3)
  /// [timeStepSeconds]: فاصله زمانی بین هر گام (پیش‌فرض: 5)
  /// 
  /// Returns: PathPredictionResult شامل موقعیت‌های پیش‌بینی شده
  Future<PathPredictionResult> predictPathWithMarkov({
    required String deviceId,
    int steps = 3,
    int timeStepSeconds = 5,
  }) async {
    try {
      // دریافت تاریخچه موقعیت
      final history = await _database.getLocationHistory(
        deviceId: deviceId,
        limit: 100,
        ascending: false,
      );

      if (history.length < 2) {
        // اگر تاریخچه کافی نیست، از روش ساده استفاده می‌کنیم
        return await _predictWithVelocity(deviceId, steps, timeStepSeconds);
      }

      // ساخت مدل انتقال مارکوف
      final markovModel = _buildMarkovModel(history);

      // پیش‌بینی ناحیه بعدی
      final predictedZone = _predictNextZone(history, markovModel);

      // پیش‌بینی موقعیت‌های آینده
      final predictions = <PredictedLocation>[];
      final lastLocation = history.first;
      final now = DateTime.now();

      // اگر ناحیه پیش‌بینی شده داریم، از آن استفاده می‌کنیم
      if (predictedZone != null) {
        // پیدا کردن موقعیت‌های قبلی در این ناحیه
        final zoneLocations = history
            .where((loc) => loc.zoneLabel == predictedZone)
            .take(5)
            .toList();

        if (zoneLocations.isNotEmpty) {
          // استفاده از میانگین موقعیت‌های این ناحیه
          final avgLat = zoneLocations
                  .map((l) => l.latitude)
                  .reduce((a, b) => a + b) /
              zoneLocations.length;
          final avgLon = zoneLocations
                  .map((l) => l.longitude)
                  .reduce((a, b) => a + b) /
              zoneLocations.length;

          for (int i = 1; i <= steps; i++) {
            predictions.add(PredictedLocation(
              latitude: avgLat,
              longitude: avgLon,
              timestamp: now.add(Duration(seconds: i * timeStepSeconds)),
              confidence: (0.6 * math.pow(0.85, i)).clamp(0.2, 0.6),
              zoneLabel: predictedZone,
            ));
          }
        }
      }

      // اگر پیش‌بینی ناحیه موفق نبود، از سرعت استفاده می‌کنیم
      if (predictions.isEmpty) {
        return await _predictWithVelocity(deviceId, steps, timeStepSeconds);
      }

      final overallConfidence = predictions
              .map((p) => p.confidence)
              .reduce((a, b) => a + b) /
          predictions.length;

      debugPrint(
        'Markov prediction: Zone=$predictedZone, '
        'Steps=$steps, Confidence=${overallConfidence.toStringAsFixed(2)}',
      );

      return PathPredictionResult(
        predictedLocations: predictions,
        overallConfidence: overallConfidence,
        predictedZone: predictedZone,
        predictionMethod: 'Markov Chain',
      );
    } catch (e) {
      debugPrint('Error in Markov prediction: $e');
      // Fallback به روش سرعت
      return await _predictWithVelocity(deviceId, steps, timeStepSeconds);
    }
  }

  /// ساخت مدل انتقال مارکوف از تاریخچه
  /// 
  /// این متد ماتریس انتقال بین نواحی را می‌سازد.
  Map<String, Map<String, int>> _buildMarkovModel(
      List<LocationHistoryEntry> history) {
    final transitions = <String, Map<String, int>>{};

    for (int i = 0; i < history.length - 1; i++) {
      final current = _normalizeZone(history[i]);
      final next = _normalizeZone(history[i + 1]);

      transitions.putIfAbsent(current, () => {});
      transitions[current]![next] = (transitions[current]![next] ?? 0) + 1;
    }

    return transitions;
  }

  /// پیش‌بینی ناحیه بعدی با استفاده از مدل مارکوف
  String? _predictNextZone(
    List<LocationHistoryEntry> history,
    Map<String, Map<String, int>> markovModel,
  ) {
    if (history.isEmpty || markovModel.isEmpty) return null;

    final lastZone = _normalizeZone(history.first);
    final nextCounts = markovModel[lastZone];

    if (nextCounts == null || nextCounts.isEmpty) return null;

    // پیدا کردن ناحیه با بیشترین احتمال
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

    // اگر احتمال کافی باشد (بیش از 30%)
    if (total > 0 && bestCount / total >= 0.3) {
      return bestZone;
    }

    return null;
  }

  /// نرمال‌سازی ناحیه (تبدیل به شناسه یکتا)
  String _normalizeZone(LocationHistoryEntry entry) {
    if (entry.zoneLabel != null && entry.zoneLabel!.isNotEmpty) {
      return entry.zoneLabel!;
    }

    // اگر لیبل وجود ندارد، از گرید تقریبی استفاده می‌کنیم
    final latBucket = entry.latitude.toStringAsFixed(4);
    final lonBucket = entry.longitude.toStringAsFixed(4);
    return '$latBucket,$lonBucket';
  }

  /// پیش‌بینی مسیر با استفاده از سرعت و جهت
  /// 
  /// این متد از آخرین سرعت و جهت حرکت برای پیش‌بینی استفاده می‌کند.
  Future<PathPredictionResult> _predictWithVelocity(
    String deviceId,
    int steps,
    int timeStepSeconds,
  ) async {
    try {
      final trajectory = await _trajectoryService.getRecentTrajectory(
        deviceId: deviceId,
        limit: 10,
      );

      if (trajectory.length < 2) {
        // اگر تاریخچه کافی نیست، موقعیت فعلی را برمی‌گردانیم
        if (trajectory.isEmpty) {
          return PathPredictionResult(
            predictedLocations: [],
            overallConfidence: 0.0,
            predictionMethod: 'Velocity-based (insufficient data)',
          );
        }

        final last = trajectory.last;
        final predictions = List.generate(steps, (i) {
          return PredictedLocation(
            latitude: last.latitude,
            longitude: last.longitude,
            timestamp: DateTime.now()
                .add(Duration(seconds: (i + 1) * timeStepSeconds)),
            confidence: 0.1,
            zoneLabel: last.zoneLabel,
          );
        });

        return PathPredictionResult(
          predictedLocations: predictions,
          overallConfidence: 0.1,
          predictionMethod: 'Velocity-based (static)',
        );
      }

      // محاسبه سرعت و جهت
      final speed = _trajectoryService.calculateSpeed(trajectory);
      final direction = _trajectoryService.calculateDirection(trajectory);

      // تبدیل سرعت از m/s به درجه جغرافیایی بر ثانیه
      // تقریب: 1 درجه ≈ 111 کیلومتر
      const degreesPerMeter = 1.0 / 111000.0;
      final latVelocity = speed * degreesPerMeter * math.cos(direction);
      final lonVelocity = speed * degreesPerMeter * math.sin(direction);

      final predictions = <PredictedLocation>[];
      final last = trajectory.last;
      final now = DateTime.now();

      for (int i = 1; i <= steps; i++) {
        final timeDelta = i * timeStepSeconds;
        final predictedLat = last.latitude + latVelocity * timeDelta;
        final predictedLon = last.longitude + lonVelocity * timeDelta;

        // کاهش confidence با افزایش فاصله زمانی
        final confidence = (last.confidence * math.pow(0.8, i)).clamp(0.1, 0.6);

        predictions.add(PredictedLocation(
          latitude: predictedLat,
          longitude: predictedLon,
          timestamp: now.add(Duration(seconds: timeDelta)),
          confidence: confidence,
          zoneLabel: last.zoneLabel,
        ));
      }

      final overallConfidence = predictions
              .map((p) => p.confidence)
              .reduce((a, b) => a + b) /
          predictions.length;

      debugPrint(
        'Velocity prediction: Speed=${speed.toStringAsFixed(2)} m/s, '
        'Direction=${(direction * 180 / math.pi).toStringAsFixed(1)}°, '
        'Confidence=${overallConfidence.toStringAsFixed(2)}',
      );

      return PathPredictionResult(
        predictedLocations: predictions,
        overallConfidence: overallConfidence,
        predictionMethod: 'Velocity-based',
      );
    } catch (e) {
      debugPrint('Error in velocity prediction: $e');
      return PathPredictionResult(
        predictedLocations: [],
        overallConfidence: 0.0,
        predictionMethod: 'Error',
      );
    }
  }

  /// پیش‌بینی مسیر با استفاده از N-gram
  /// 
  /// این متد از آخرین N حرکت کاربر برای پیش‌بینی استفاده می‌کند.
  Future<PathPredictionResult> predictPathWithNGram({
    required String deviceId,
    int n = 3, // طول N-gram
    int steps = 3,
    int timeStepSeconds = 5,
  }) async {
    try {
      final history = await _database.getLocationHistory(
        deviceId: deviceId,
        limit: 100,
        ascending: false,
      );

      if (history.length < n + 1) {
        // اگر تاریخچه کافی نیست، از روش سرعت استفاده می‌کنیم
        return await _predictWithVelocity(deviceId, steps, timeStepSeconds);
      }

      // ساخت N-gram از آخرین N+1 موقعیت
      final ngram = history.take(n + 1).toList().reversed.toList();

      // جستجوی الگوهای مشابه در تاریخچه
      final similarPatterns = _findSimilarPatterns(ngram, history, n);

      if (similarPatterns.isEmpty) {
        // اگر الگوی مشابهی پیدا نشد، از روش سرعت استفاده می‌کنیم
        return await _predictWithVelocity(deviceId, steps, timeStepSeconds);
      }

      // استفاده از الگوی مشابه برای پیش‌بینی
      final nextLocation = similarPatterns.first;
      final predictions = <PredictedLocation>[];
      final now = DateTime.now();

      for (int i = 1; i <= steps; i++) {
        predictions.add(PredictedLocation(
          latitude: nextLocation.latitude,
          longitude: nextLocation.longitude,
          timestamp: now.add(Duration(seconds: i * timeStepSeconds)),
          confidence: (0.5 * math.pow(0.85, i)).clamp(0.2, 0.5),
          zoneLabel: nextLocation.zoneLabel,
        ));
      }

      final overallConfidence = predictions
              .map((p) => p.confidence)
              .reduce((a, b) => a + b) /
          predictions.length;

      return PathPredictionResult(
        predictedLocations: predictions,
        overallConfidence: overallConfidence,
        predictionMethod: 'N-gram (N=$n)',
      );
    } catch (e) {
      debugPrint('Error in N-gram prediction: $e');
      return await _predictWithVelocity(deviceId, steps, timeStepSeconds);
    }
  }

  /// پیدا کردن الگوهای مشابه در تاریخچه
  List<LocationHistoryEntry> _findSimilarPatterns(
    List<LocationHistoryEntry> ngram,
    List<LocationHistoryEntry> history,
    int n,
  ) {
    final similar = <LocationHistoryEntry>[];
    const threshold = 0.0005; // حدود 50 متر

    for (int i = 0; i <= history.length - n - 1; i++) {
      bool isSimilar = true;

      // مقایسه N موقعیت اول
      for (int j = 0; j < n; j++) {
        final latDiff = (ngram[j].latitude - history[i + j].latitude).abs();
        final lonDiff = (ngram[j].longitude - history[i + j].longitude).abs();

        if (latDiff > threshold || lonDiff > threshold) {
          isSimilar = false;
          break;
        }
      }

      if (isSimilar && i + n < history.length) {
        similar.add(history[i + n]);
      }
    }

    return similar;
  }
}

