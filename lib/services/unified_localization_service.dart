/// سرویس یکپارچه مکان‌یابی GPS-Free با تلفیق وای‌فای + BTS
///
/// - تشخیص محیط با در نظر گرفتن داده سلولی (Indoor/Outdoor/Hybrid)
/// - فیوژن وزن‌دار در حالت Hybrid بر اساس تعداد AP/دکل و قدرت سیگنال
/// - آستانه‌های هوشمند برای سوئیچ بین محیط‌ها
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import 'indoor_localization_service.dart';
import 'outdoor_localization_service.dart';
import 'trajectory_service.dart';
import 'path_prediction_service.dart';

// آستانه‌های تشخیص محیط
const int _kMinApForIndoor = 3;
const double _kMinWifiStrengthForIndoor = 0.25;
const int _kMinTowersForOutdoor = 1;
const double _kMinCellStrengthForOutdoor = -110.0; // dBm
const double _kMinWifiStrengthForHybrid = 0.2;
const double _kMinCellConfidenceForHybrid = 0.15;

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

  /// انجام مکان‌یابی یکپارچه با تشخیص محیط و فیوژن هوشمند
  ///
  /// 1. تشخیص محیط با در نظر گرفتن وای‌فای و داده سلولی
  /// 2. در Hybrid: وزن وای‌فای = f(تعداد AP، میانگین RSSI)، وزن سلولی = f(تعداد دکل، قدرت سیگنال)
  /// 3. موقعیت نهایی = (موقعیت_وای‌فای×وزن_وای‌فای + موقعیت_سلولی×وزن_سلولی) / مجموع_وزن‌ها
  Future<UnifiedLocalizationResult> performLocalization({
    required String deviceId,
    bool preferIndoor = true,
  }) async {
    try {
      final indoorFuture = _indoorService.performIndoorLocalization();
      final outdoorFuture = _outdoorService.performOutdoorLocalization();
      final indoorResult = await indoorFuture;
      final outdoorResult = await outdoorFuture;

      final env = _classifyEnvironment(indoorResult, outdoorResult, preferIndoor);
      LocationEstimate? finalEstimate;
      double confidence;

      if (env == 'hybrid' &&
          indoorResult.estimate != null &&
          outdoorResult.estimate != null) {
        final wWifi = _wifiFusionWeight(
          indoorResult.accessPointCount,
          indoorResult.wifiStrength,
        );
        final wCell = _cellFusionWeight(
          outdoorResult.cellTowerCount,
          outdoorResult.averageSignalStrength,
          outdoorResult.estimate!.confidence,
        );
        final sumW = wWifi + wCell;
        if (sumW > 0) {
          final lat = (indoorResult.estimate!.latitude * wWifi +
                  outdoorResult.estimate!.latitude * wCell) /
              sumW;
          final lon = (indoorResult.estimate!.longitude * wWifi +
                  outdoorResult.estimate!.longitude * wCell) /
              sumW;
          confidence = (indoorResult.estimate!.confidence * wWifi +
                  outdoorResult.estimate!.confidence * wCell) /
              sumW;
          confidence = confidence.clamp(0.0, 1.0);
          finalEstimate = LocationEstimate(
            latitude: lat,
            longitude: lon,
            confidence: confidence,
            zoneLabel: indoorResult.estimate!.zoneLabel ??
                outdoorResult.estimate!.zoneLabel,
            nearestNeighbors: indoorResult.estimate!.nearestNeighbors,
            averageDistance: (indoorResult.estimate!.averageDistance +
                    outdoorResult.estimate!.averageDistance) /
                2,
          );
          debugPrint(
            'Hybrid fusion: wWifi=${wWifi.toStringAsFixed(2)}, '
            'wCell=${wCell.toStringAsFixed(2)}, conf=${confidence.toStringAsFixed(2)}',
          );
        } else {
          finalEstimate = preferIndoor ? indoorResult.estimate : outdoorResult.estimate;
          confidence = finalEstimate?.confidence ?? 0.0;
        }
      } else if (env == 'indoor') {
        finalEstimate = indoorResult.estimate;
        confidence = finalEstimate?.confidence ?? 0.0;
      } else if (env == 'outdoor') {
        finalEstimate = outdoorResult.estimate;
        confidence = finalEstimate?.confidence ?? 0.0;
      } else {
        finalEstimate = null;
        confidence = 0.0;
      }

      if (finalEstimate != null && confidence >= 0.3) {
        await _trajectoryService.addTrajectoryPoint(
          estimate: finalEstimate,
          deviceId: deviceId,
          environmentType: env,
        );
      }

      return UnifiedLocalizationResult(
        estimate: finalEstimate,
        environmentType: env,
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

  /// تشخیص محیط با در نظر گرفتن وای‌فای و داده سلولی
  String _classifyEnvironment(
    IndoorLocalizationResult indoorResult,
    OutdoorLocalizationResult outdoorResult,
    bool preferIndoor,
  ) {
    final hasIndoor = indoorResult.isIndoor && indoorResult.isReliable;
    final hasOutdoor = outdoorResult.isOutdoor && outdoorResult.isReliable;
    final wifiOk = indoorResult.accessPointCount >= _kMinApForIndoor &&
        indoorResult.wifiStrength >= _kMinWifiStrengthForHybrid;
    final cellOk = outdoorResult.cellTowerCount >= _kMinTowersForOutdoor &&
        outdoorResult.averageSignalStrength >= _kMinCellStrengthForOutdoor &&
        (outdoorResult.estimate?.confidence ?? 0) >= _kMinCellConfidenceForHybrid;

    if (hasIndoor && hasOutdoor && wifiOk && cellOk) return 'hybrid';
    if (hasIndoor) return 'indoor';
    if (hasOutdoor) return 'outdoor';
    if (indoorResult.accessPointCount >= _kMinApForIndoor &&
        indoorResult.wifiStrength >= _kMinWifiStrengthForIndoor) return 'indoor';
    if (outdoorResult.cellTowerCount >= _kMinTowersForOutdoor) return 'outdoor';
    return 'unknown';
  }

  /// وزن وای‌فای برای فیوژن: تابعی از تعداد AP و میانگین RSSI (قدرت)
  double _wifiFusionWeight(int apCount, double wifiStrength) {
    final apFactor = (apCount / 6.0).clamp(0.0, 1.0);
    return (apFactor * 0.4 + wifiStrength * 0.6).clamp(0.0, 1.0);
  }

  /// وزن سلولی برای فیوژن: تابعی از تعداد دکل و قدرت سیگنال
  double _cellFusionWeight(int towerCount, double avgSignalDbm, double cellConfidence) {
    final countFactor = (towerCount / 5.0).clamp(0.0, 1.0);
    final signalFactor = ((avgSignalDbm + 120) / 70).clamp(0.0, 1.0);
    return (countFactor * 0.3 + signalFactor * 0.4 + cellConfidence * 0.3).clamp(0.0, 1.0);
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

