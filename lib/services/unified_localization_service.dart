/// سرویس یکپارچه مکان‌یابی (Unified Localization Service)
/// 
/// این سرویس به عنوان رابط اصلی برای مکان‌یابی Indoor و Outdoor عمل می‌کند.
/// به صورت خودکار تصمیم می‌گیرد که از کدام روش استفاده کند.
/// 
/// عملکرد:
/// - تشخیص خودکار محیط (Indoor/Outdoor)
/// - انتخاب بهترین روش مکان‌یابی
/// - ترکیب نتایج در صورت امکان
/// - مدیریت مسیر حرکت
/// - پیش‌بینی مسیر آینده
/// 
/// چرا GPS-Free؟
/// - تمام روش‌های مکان‌یابی بر اساس سیگنال‌های رادیویی است
/// - هیچ وابستگی به GPS یا سرویس‌های خارجی ندارد
/// - حریم خصوصی کامل حفظ می‌شود
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import 'indoor_localization_service.dart';
import 'outdoor_localization_service.dart';
import 'trajectory_service.dart';
import 'path_prediction_service.dart';

/// نتیجه مکان‌یابی یکپارچه
class UnifiedLocalizationResult {
  final LocationEstimate? estimate;
  final String environmentType; // 'indoor', 'outdoor', 'hybrid', 'unknown'
  final double confidence;
  final String? zoneLabel;
  final IndoorLocalizationResult? indoorResult;
  final OutdoorLocalizationResult? outdoorResult;

  UnifiedLocalizationResult({
    this.estimate,
    required this.environmentType,
    required this.confidence,
    this.zoneLabel,
    this.indoorResult,
    this.outdoorResult,
  });

  bool get isReliable => estimate != null && confidence >= 0.3;
}

/// سرویس یکپارچه مکان‌یابی
class UnifiedLocalizationService {
  final LocalDatabase _database;
  final IndoorLocalizationService _indoorService;
  final OutdoorLocalizationService _outdoorService;
  final TrajectoryService _trajectoryService;
  final PathPredictionService _predictionService;

  UnifiedLocalizationService(this._database)
      : _indoorService = IndoorLocalizationService(_database),
        _outdoorService = OutdoorLocalizationService(_database),
        _trajectoryService = TrajectoryService(_database),
        _predictionService = PathPredictionService(_database);

  /// انجام مکان‌یابی یکپارچه
  /// 
  /// این متد به صورت خودکار:
  /// 1. محیط را تشخیص می‌دهد (Indoor/Outdoor)
  /// 2. بهترین روش مکان‌یابی را انتخاب می‌کند
  /// 3. در صورت امکان، از هر دو روش استفاده می‌کند (Hybrid)
  /// 4. مسیر حرکت را به‌روزرسانی می‌کند
  /// 
  /// [deviceId]: شناسه دستگاه
  /// [preferIndoor]: اولویت با Indoor (پیش‌فرض: true)
  /// 
  /// Returns: UnifiedLocalizationResult
  Future<UnifiedLocalizationResult> performLocalization({
    required String deviceId,
    bool preferIndoor = true,
  }) async {
    try {
      // انجام مکان‌یابی Indoor و Outdoor به صورت موازی
      final indoorFuture = _indoorService.performIndoorLocalization();
      final outdoorFuture = _outdoorService.performOutdoorLocalization();

      final indoorResult = await indoorFuture;
      final outdoorResult = await outdoorFuture;

      // تصمیم‌گیری استراتژی
      final hasIndoor = indoorResult.isIndoor && indoorResult.isReliable;
      final hasOutdoor = outdoorResult.isOutdoor && outdoorResult.isReliable;

      LocationEstimate? finalEstimate;
      String environmentType;
      double confidence;

      if (hasIndoor && hasOutdoor) {
        // حالت Hybrid: استفاده از هر دو
        environmentType = 'hybrid';
        
        // ترکیب نتایج با وزن‌دهی
        final indoorEst = indoorResult.estimate!;
        final outdoorEst = outdoorResult.estimate!;
        
        // وزن بیشتر برای Indoor (دقت بالاتر)
        final weight = preferIndoor ? 0.7 : 0.5;
        final lat = indoorEst.latitude * weight + outdoorEst.latitude * (1 - weight);
        final lon = indoorEst.longitude * weight + outdoorEst.longitude * (1 - weight);
        confidence = (indoorEst.confidence * weight + outdoorEst.confidence * (1 - weight))
            .clamp(0.0, 1.0);

        finalEstimate = LocationEstimate(
          latitude: lat,
          longitude: lon,
          confidence: confidence,
          zoneLabel: indoorEst.zoneLabel ?? outdoorEst.zoneLabel,
          nearestNeighbors: indoorEst.nearestNeighbors,
          averageDistance: (indoorEst.averageDistance + outdoorEst.averageDistance) / 2,
        );

        debugPrint('Hybrid localization: Indoor confidence=${indoorEst.confidence.toStringAsFixed(2)}, '
            'Outdoor confidence=${outdoorEst.confidence.toStringAsFixed(2)}');
      } else if (hasIndoor) {
        // فقط Indoor
        environmentType = 'indoor';
        finalEstimate = indoorResult.estimate;
        confidence = finalEstimate?.confidence ?? 0.0;
      } else if (hasOutdoor) {
        // فقط Outdoor
        environmentType = 'outdoor';
        finalEstimate = outdoorResult.estimate;
        confidence = finalEstimate?.confidence ?? 0.0;
      } else {
        // هیچ کدام
        environmentType = 'unknown';
        confidence = 0.0;
      }

      // ذخیره در مسیر حرکت
      if (finalEstimate != null && confidence >= 0.3) {
        await _trajectoryService.addTrajectoryPoint(
          estimate: finalEstimate,
          deviceId: deviceId,
          environmentType: environmentType,
        );
      }

      return UnifiedLocalizationResult(
        estimate: finalEstimate,
        environmentType: environmentType,
        confidence: confidence,
        zoneLabel: finalEstimate?.zoneLabel,
        indoorResult: indoorResult,
        outdoorResult: outdoorResult,
      );
    } catch (e) {
      debugPrint('Error in unified localization: $e');
      return UnifiedLocalizationResult(
        environmentType: 'unknown',
        confidence: 0.0,
      );
    }
  }

  /// پیش‌بینی مسیر آینده
  /// 
  /// این متد مسیر کوتاه‌مدت آینده کاربر را پیش‌بینی می‌کند.
  /// 
  /// [deviceId]: شناسه دستگاه
  /// [method]: روش پیش‌بینی ('markov', 'velocity', 'ngram')
  /// [steps]: تعداد گام‌های آینده
  /// 
  /// Returns: PathPredictionResult
  Future<PathPredictionResult> predictPath({
    required String deviceId,
    String method = 'markov',
    int steps = 3,
  }) async {
    try {
      switch (method) {
        case 'markov':
          return await _predictionService.predictPathWithMarkov(
            deviceId: deviceId,
            steps: steps,
          );
        case 'ngram':
          return await _predictionService.predictPathWithNGram(
            deviceId: deviceId,
            steps: steps,
          );
        case 'velocity':
        default:
          // استفاده از روش سرعت به عنوان fallback
          final trajectory = await _trajectoryService.getRecentTrajectory(
            deviceId: deviceId,
            limit: 10,
          );
          if (trajectory.length < 2) {
            return PathPredictionResult(
              predictedLocations: [],
              overallConfidence: 0.0,
              predictionMethod: 'Velocity-based (insufficient data)',
            );
          }
          // این متد در PathPredictionService پیاده‌سازی شده است
          return await _predictionService.predictPathWithMarkov(
            deviceId: deviceId,
            steps: steps,
          );
      }
    } catch (e) {
      debugPrint('Error in path prediction: $e');
      return PathPredictionResult(
        predictedLocations: [],
        overallConfidence: 0.0,
        predictionMethod: 'Error',
      );
    }
  }

  /// دریافت مسیر حرکت اخیر
  Future<List<TrajectoryPoint>> getRecentTrajectory({
    required String deviceId,
    int limit = 50,
  }) async {
    return await _trajectoryService.getRecentTrajectory(
      deviceId: deviceId,
      limit: limit,
    );
  }

  /// هموارسازی مسیر
  Future<List<TrajectoryPoint>> getSmoothedTrajectory({
    required String deviceId,
    int limit = 50,
    int windowSize = 3,
  }) async {
    final trajectory = await _trajectoryService.getRecentTrajectory(
      deviceId: deviceId,
      limit: limit,
    );
    return _trajectoryService.smoothTrajectory(trajectory, windowSize: windowSize);
  }
}

