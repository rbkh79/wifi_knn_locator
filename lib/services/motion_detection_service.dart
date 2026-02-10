import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// وضعیت حرکت کاربر
enum MotionState {
  stationary, // ساکن
  walking, // در حال راه رفتن
  unknown, // نامشخص / در حال تغییر
}

class _AccelSample {
  final DateTime t;
  final double valueG; // شتاب خطی فیلتر شده (بر حسب g)

  _AccelSample(this.t, this.valueG);
}

/// سرویس تشخیص حرکت بر اساس شتاب‌سنج + فیلتر کالمن ساده
///
/// - پنجره زمانی ~۲ ثانیه
/// - تشخیص قدم‌زنی با:
///   * فرکانس قدم ~ 1.5–2.5 Hz
///   * دامنه شتاب > 0.3g
class MotionDetectionService {
  final _stateController = StreamController<MotionState>.broadcast();
  MotionState _currentState = MotionState.unknown;

  // تنظیمات الگوریتم
  final Duration window = const Duration(seconds: 2);
  final double minStepAmplitudeG = 0.3;
  final double minStepFreqHz = 1.5;
  final double maxStepFreqHz = 2.5;
  final Duration minStepInterval = const Duration(milliseconds: 300);

  // فیلتر کالمن ۱ بعدی روی قدر مطلق شتاب خطی
  double _kalmanEstimate = 0.0;
  double _kalmanError = 1.0;
  final double _processNoiseQ = 0.01;
  final double _measurementNoiseR = 0.1;

  final List<_AccelSample> _samples = [];
  StreamSubscription<AccelerometerEvent>? _accSub;
  DateTime _lastStepTime = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<MotionState> get motionStateStream => _stateController.stream;
  MotionState get currentState => _currentState;

  /// شروع گوش‌دادن به سنسورها
  void start() {
    if (_accSub != null) return;
    _accSub = accelerometerEvents.listen(_onAccelerometer);
  }

  /// توقف سرویس
  void stop() {
    _accSub?.cancel();
    _accSub = null;
    _samples.clear();
  }

  void _onAccelerometer(AccelerometerEvent e) {
    final now = DateTime.now();

    // قدر مطلق شتاب (m/s^2)
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    // تفریق تقریبی گرانش -> شتاب خطی
    final linAcc = (mag - 9.81).clamp(-30.0, 30.0);

    // تبدیل به g
    final linG = linAcc / 9.81;

    // به‌روز کردن فیلتر کالمن
    final filteredG = _kalmanUpdate(linG.toDouble());

    // ذخیره در پنجره زمانی
    _samples.add(_AccelSample(now, filteredG));
    _pruneOldSamples(now);

    // هر بار که داده جدید می‌آید، وضعیت حرکت را دوباره ارزیابی کن
    _evaluateMotionState(now);
  }

  double _kalmanUpdate(double measurement) {
    // پیش‌بینی
    _kalmanError += _processNoiseQ;

    // به‌روزرسانی
    final k = _kalmanError / (_kalmanError + _measurementNoiseR);
    _kalmanEstimate = _kalmanEstimate + k * (measurement - _kalmanEstimate);
    _kalmanError = (1 - k) * _kalmanError;
    return _kalmanEstimate;
  }

  void _pruneOldSamples(DateTime now) {
    _samples.removeWhere((s) => now.difference(s.t) > window);
  }

  void _evaluateMotionState(DateTime now) {
    if (_samples.length < 10) {
      _setState(MotionState.unknown);
      return;
    }

    // پیدا کردن قله‌ها (peaks) برای تشخیص قدم
    final peaks = <DateTime>[];
    for (int i = 1; i < _samples.length - 1; i++) {
      final prev = _samples[i - 1];
      final cur = _samples[i];
      final next = _samples[i + 1];

      final isPeak = cur.valueG > minStepAmplitudeG &&
          cur.valueG > prev.valueG &&
          cur.valueG > next.valueG;

      if (!isPeak) continue;

      if (peaks.isEmpty ||
          cur.t.difference(peaks.last) >= minStepInterval) {
        peaks.add(cur.t);
      }
    }

    if (peaks.length < 2) {
      // دامنه خیلی کم یا تعداد قدم کم -> احتمالاً ساکن
      final std = _stdDev(_samples.map((s) => s.valueG).toList());
      if (std < 0.05) {
        _setState(MotionState.stationary);
      } else {
        _setState(MotionState.unknown);
      }
      return;
    }

    // فرکانس قدم (Hz) روی پنجره
    final durationSec = window.inMilliseconds / 1000.0;
    final stepFreq = peaks.length / durationSec;

    if (stepFreq >= minStepFreqHz && stepFreq <= maxStepFreqHz) {
      _setState(MotionState.walking);
      _lastStepTime = peaks.last;
    } else {
      // اگر تازه از راه‌رفتن خارج شده باشیم، احتمال توقف ناگهانی
      final timeSinceLastPeak =
          now.difference(peaks.last).inMilliseconds / 1000.0;
      if (timeSinceLastPeak < 1.0) {
        _setState(MotionState.walking);
      } else {
        _setState(MotionState.stationary);
      }
    }
  }

  double _stdDev(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean =
        values.reduce((a, b) => a + b) / values.length.toDouble();
    final varSum = values
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b);
    return math.sqrt(varSum / values.length.toDouble());
  }

  void _setState(MotionState newState) {
    if (newState == _currentState) return;
    _currentState = newState;
    _stateController.add(newState);
  }

  /// پیشنهاد فاصله اسکن بر اساس وضعیت حرکت
  Duration get recommendedScanInterval {
    switch (_currentState) {
      case MotionState.walking:
        return const Duration(seconds: 3); // حالت راه رفتن
      case MotionState.stationary:
        return const Duration(seconds: 15); // حالت ساکن
      case MotionState.unknown:
      default:
        return const Duration(seconds: 8); // حد وسط
    }
  }

  /// آیا به‌تازگی توقف ناگهانی رخ داده است؟ (walk -> stationary)
  bool get justStopped {
    final now = DateTime.now();
    return _currentState == MotionState.stationary &&
        now.difference(_lastStepTime) < const Duration(seconds: 2);
  }

  void dispose() {
    stop();
    _stateController.close();
  }
}

