import 'package:flutter/material.dart';
import '../data_model.dart';

/// سرویس مدیریت کنترل‌کننده نقشه و انتقال‌های نرم
class MapControllerService extends ChangeNotifier {
  // موقعیت فعلی
  LocationEstimate? _currentPosition;
  LocationEstimate? get currentPosition => _currentPosition;

  // موقعیت قبلی (برای ردیابی تغییرات)
  LocationEstimate? _previousPosition;

  // انیمیشن
  late AnimationController? _animationController;

  // تاریخچه موقعیت‌ها
  final List<LocationEstimate> _positionHistory = [];
  List<LocationEstimate> get positionHistory =>
      List.unmodifiable(_positionHistory);

  // حالت بارگذاری
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // حداکثر تعداد نقاط در تاریخچه
  static const int maxHistorySize = 100;

  /// به‌روزرسانی موقعیت فعلی
  Future<void> updatePosition(
    LocationEstimate newPosition, {
    AnimationController? animationController,
    Duration animationDuration = const Duration(milliseconds: 1000),
  }) async {
    _previousPosition = _currentPosition;
    _currentPosition = newPosition;

    // افزودن به تاریخچه
    _addToHistory(newPosition);

    // تشغیل انیمیشن اگر controller فراهم شده باشد
    if (animationController != null) {
      animationController.duration = animationDuration;
      animationController.forward(from: 0);
    }

    notifyListeners();
  }

  /// افزودن موقعیت به تاریخچه
  void _addToHistory(LocationEstimate position) {
    _positionHistory.add(position);
    if (_positionHistory.length > maxHistorySize) {
      _positionHistory.removeAt(0);
    }
  }

  /// پاک کردن تاریخچه
  void clearHistory() {
    _positionHistory.clear();
    notifyListeners();
  }

  /// بررسی اگر موقعیت پرش بزرگ داشته باشد
  bool hasLargePositionJump() {
    if (_previousPosition == null || _currentPosition == null) return false;

    final distance = _calculateDistance(
      _previousPosition!.latitude,
      _previousPosition!.longitude,
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    // اگر فاصله بیش از 1 کیلومتر باشد (تقریبی)
    return distance > 0.009; // ~1 km in degrees
  }

  /// محاسبه فاصله بین دو نقطه (تقریب ساده)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return ((lat2 - lat1).abs() + (lon2 - lon1).abs()) / 2;
  }

  /// تعیین اگر اطمینان کم باشد
  bool hasLowConfidence() {
    return _currentPosition != null && _currentPosition!.confidence < 0.3;
  }

  /// تعیین اگر اطمینان خیلی کم باشد
  bool hasVeryLowConfidence() {
    return _currentPosition != null && _currentPosition!.confidence < 0.15;
  }

  /// مختصات فعلی به صورت رشته
  String getCurrentCoordinatesString() {
    if (_currentPosition == null) return 'N/A';
    return '${_currentPosition!.latitude.toStringAsFixed(6)}, '
        '${_currentPosition!.longitude.toStringAsFixed(6)}';
  }

  /// مختصات فعلی با درصد اطمینان
  String getCurrentCoordinatesWithConfidence() {
    if (_currentPosition == null) return 'N/A';
    final conf = (_currentPosition!.confidence * 100).toStringAsFixed(0);
    return '${_currentPosition!.latitude.toStringAsFixed(6)}, '
        '${_currentPosition!.longitude.toStringAsFixed(6)} ($conf%)';
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }
}

/// سرویس تصفیه موقعیت (filtering)
class PositionFilterService {
  // فیلتر Kalman ساده
  LocationEstimate? _lastFiltered;
  static const double kalmanGain = 0.7;

  /// اعمال فیلتر هموارسازی بر موقعیت
  LocationEstimate applyPositionFilter(LocationEstimate rawPosition) {
    if (_lastFiltered == null) {
      _lastFiltered = rawPosition;
      return rawPosition;
    }

    // Kalman filter ساده برای موقعیت
    final filteredLat = (_lastFiltered!.latitude * (1 - kalmanGain)) +
        (rawPosition.latitude * kalmanGain);
    final filteredLon = (_lastFiltered!.longitude * (1 - kalmanGain)) +
        (rawPosition.longitude * kalmanGain);

    // اطمینان: میانگین موزون
    final filteredConfidence = (_lastFiltered!.confidence * (1 - kalmanGain)) +
        (rawPosition.confidence * kalmanGain);

    final filtered = LocationEstimate(
      latitude: filteredLat,
      longitude: filteredLon,
      confidence: filteredConfidence,
      zoneLabel: rawPosition.zoneLabel,
      nearestNeighbors: rawPosition.nearestNeighbors,
      averageDistance: rawPosition.averageDistance,
    );

    _lastFiltered = filtered;
    return filtered;
  }

  /// بازنشانی فیلتر
  void reset() {
    _lastFiltered = null;
  }
}

/// سرویس انیمیشن برای نقشه
class MapAnimationService {
  static const Duration zoomAnimationDuration = Duration(milliseconds: 600);
  static const Duration panAnimationDuration = Duration(milliseconds: 800);

  /// انیمیشن زوم هنگام به‌روزرسانی موقعیت
  static Future<void> animateZoom(
    AnimationController controller,
    Duration duration = zoomAnimationDuration,
  ) async {
    controller.duration = duration;
    await controller.forward();
    controller.reset();
  }

  /// انیمیشن پن (حرکت نقشه)
  static Future<void> animatePan(
    AnimationController controller,
    Duration duration = panAnimationDuration,
  ) async {
    controller.duration = duration;
    await controller.forward();
    controller.reset();
  }

  /// انیمیشن رادار هنگام اسکن
  static Animation<double> createRadarAnimation(
    AnimationController controller,
    Duration duration = const Duration(milliseconds: 1500),
  ) {
    controller.duration = duration;
    controller.repeat();
    return Tween<double>(begin: 0, end: 1).animate(controller);
  }

  /// انیمیشن پالس (موج)
  static Animation<double> createPulseAnimation(
    AnimationController controller,
    Duration duration = const Duration(milliseconds: 2000),
  ) {
    controller.duration = duration;
    controller.repeat(reverse: true);
    return Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
  }
}
