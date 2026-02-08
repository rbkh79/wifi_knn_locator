import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../knn_localization.dart';
import '../cell_scanner.dart';

/// نتیجه مکان‌یابی خارجی (Outdoor)
class OutdoorLocalizationResult {
  final LocationEstimate? estimate;
  final bool isOutdoor;
  final int cellTowerCount;
  final double averageSignalStrength;
  /// واریانس قدرت سیگنال (پایین = پایدارتر، اعتماد بالاتر)
  final double signalVariance;

  OutdoorLocalizationResult({
    this.estimate,
    required this.isOutdoor,
    required this.cellTowerCount,
    required this.averageSignalStrength,
    this.signalVariance = 0.0,
  });

  bool get isReliable =>
      estimate != null &&
      estimate!.confidence >= 0.2 &&
      cellTowerCount >= 1;
}

/// سرویس مکان‌یابی خارجی مبتنی بر دکل‌های مخابراتی (BTS)
///
/// - KNN روی اثرانگشت‌های سلولی
/// - فاصله = تفاوت سیگنال دکل‌های مشترک (وزن‌دار)
/// - موقعیت = میانگین وزن‌دار نزدیک‌ترین اثرانگشت‌ها
/// - اعتماد = تابعی از تعداد دکل‌های مشترک و واریانس سیگنال
class OutdoorLocalizationService {
  final LocalDatabase _database;
  final KnnLocalization _knnLocalization;

  OutdoorLocalizationService(this._database)
      : _knnLocalization = KnnLocalization(_database);

  /// انجام مکان‌یابی خارجی
  ///
  /// [k]: تعداد همسایه‌های KNN (پیش‌فرض 3)
  Future<OutdoorLocalizationResult> performOutdoorLocalization({
    int k = 3,
  }) async {
    try {
      final isAvailable = await CellScanner.isAvailable();
      if (!isAvailable) {
        debugPrint('Outdoor localization: Cell scanner not available');
        return OutdoorLocalizationResult(
          isOutdoor: false,
          cellTowerCount: 0,
          averageSignalStrength: 0.0,
        );
      }

      final cellScan = await CellScanner.performScan();
      final allCells = cellScan.allCells;

      if (allCells.isEmpty) {
        debugPrint('Outdoor localization: No cell towers detected');
        return OutdoorLocalizationResult(
          isOutdoor: false,
          cellTowerCount: 0,
          averageSignalStrength: 0.0,
        );
      }

      final avgSignal = _averageSignalStrength(allCells);
      final variance = _signalVariance(allCells);
      final cellTowerCount = allCells.length;
      final isOutdoor = cellTowerCount >= 1;

      if (!isOutdoor) {
        return OutdoorLocalizationResult(
          isOutdoor: false,
          cellTowerCount: cellTowerCount,
          averageSignalStrength: avgSignal,
          signalVariance: variance,
        );
      }

      final estimate = await _knnLocalization.estimateLocationFromCell(
        cellScan,
        k: k,
      );

      // اعتماد نهایی: ترکیب اعتماد KNN با عامل دکل (تعداد دکل + واریانس سیگنال)
      double confidence = estimate?.confidence ?? 0.0;
      final towerFactor = _towerCountConfidenceFactor(cellTowerCount);
      final varianceFactor = _varianceConfidenceFactor(variance);
      final cellConfidence = (towerFactor * 0.5 + varianceFactor * 0.5);
      confidence = (confidence * 0.6 + cellConfidence * 0.4).clamp(0.0, 1.0);

      LocationEstimate? adjustedEstimate;
      if (estimate != null) {
        adjustedEstimate = LocationEstimate(
          latitude: estimate.latitude,
          longitude: estimate.longitude,
          confidence: confidence,
          zoneLabel: estimate.zoneLabel,
          nearestNeighbors: estimate.nearestNeighbors,
          averageDistance: estimate.averageDistance,
        );
      }

      debugPrint(
        'Outdoor localization: Cells=$cellTowerCount, '
        'AvgSignal=${avgSignal.toStringAsFixed(1)} dBm, '
        'Variance=${variance.toStringAsFixed(1)}, '
        'Confidence=${confidence.toStringAsFixed(2)}',
      );

      return OutdoorLocalizationResult(
        estimate: adjustedEstimate,
        isOutdoor: true,
        cellTowerCount: cellTowerCount,
        averageSignalStrength: avgSignal,
        signalVariance: variance,
      );
    } catch (e) {
      debugPrint('Error in outdoor localization: $e');
      return OutdoorLocalizationResult(
        isOutdoor: false,
        cellTowerCount: 0,
        averageSignalStrength: 0.0,
      );
    }
  }

  double _averageSignalStrength(List<CellTowerInfo> cells) {
    if (cells.isEmpty) return 0.0;
    final signals = cells
        .where((c) => c.signalStrength != null)
        .map((c) => c.signalStrength!.toDouble())
        .toList();
    if (signals.isEmpty) return 0.0;
    return signals.reduce((a, b) => a + b) / signals.length;
  }

  /// واریانس قدرت سیگنال (dBm). هرچه کمتر، سیگنال پایدارتر و اعتماد بیشتر.
  double _signalVariance(List<CellTowerInfo> cells) {
    final signals = cells
        .where((c) => c.signalStrength != null)
        .map((c) => c.signalStrength!.toDouble())
        .toList();
    if (signals.length < 2) return 0.0;
    final mean = signals.reduce((a, b) => a + b) / signals.length;
    final variance = signals.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / signals.length;
    return math.sqrt(variance);
  }

  /// ضریب اعتماد بر اساس تعداد دکل: بیشتر دکل => اعتماد بیشتر
  double _towerCountConfidenceFactor(int count) {
    if (count <= 0) return 0.0;
    return (count / 5.0).clamp(0.0, 1.0);
  }

  /// ضریب اعتماد بر اساس واریانس سیگنال: واریانس کم => اعتماد بیشتر
  double _varianceConfidenceFactor(double variance) {
    if (variance <= 0) return 1.0;
    return (1.0 / (1.0 + variance / 15.0)).clamp(0.0, 1.0);
  }

  Future<bool> isOutdoorEnvironment() async {
    try {
      if (!await CellScanner.isAvailable()) return false;
      final cellScan = await CellScanner.performScan();
      return cellScan.allCells.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking outdoor environment: $e');
      return false;
    }
  }
}
