import 'package:flutter/material.dart';
import '../models/environment_type.dart';

/// نشانگر سفارشی برای نمایش موقعیت تخمین‌زده‌شده بر روی نقشه
/// استایل نشانگر بر اساس نوع محیط متفاوت است
class PositionMarker extends StatelessWidget {
  final EnvironmentType environmentType;
  final double confidence;
  final bool showConfidenceRing;

  const PositionMarker({
    Key? key,
    this.environmentType = EnvironmentType.unknown,
    this.confidence = 0.5,
    this.showConfidenceRing = true,
  }) : super(key: key);

  /// رنگ نشانگر بر اساس نوع محیط
  Color _getMarkerColor() {
    switch (environmentType) {
      case EnvironmentType.indoor:
        return Colors.blue; // آبی برای داخل‌ساختمان
      case EnvironmentType.outdoor:
        return Colors.green; // سبز برای خارج
      case EnvironmentType.hybrid:
        return Colors.purple; // بنفش برای ترکیبی
      case EnvironmentType.unknown:
      default:
        return Colors.grey; // خاکستری برای نامشخص
    }
  }

  /// آیکون نشانگر بر اساس نوع محیط
  IconData _getMarkerIcon() {
    switch (environmentType) {
      case EnvironmentType.indoor:
        return Icons.location_on; // ساختمان
      case EnvironmentType.outdoor:
        return Icons.public; // نقشه
      case EnvironmentType.hybrid:
        return Icons.merge_type; // ترکیب
      case EnvironmentType.unknown:
      default:
        return Icons.help_outline; // علامت سؤال
    }
  }

  /// محاسبه شعاع حلقه اطمینان (هر چه اطمینان بیشتر، شعاع کمتر)
  double _getConfidenceRingRadius() {
    // اطمینان بالا = شعاع کوچکتر (دقت بهتر)
    // اطمینان پایین = شعاع بزرگتر (عدم قطعیت بیشتر)
    return 50 * (1 - confidence).clamp(0.2, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final markerColor = _getMarkerColor();

    return Stack(
      alignment: Alignment.center,
      children: [
        // حلقه اطمینان (اختیاری)
        if (showConfidenceRing && confidence < 0.95)
          Container(
            width: _getConfidenceRingRadius() * 2,
            height: _getConfidenceRingRadius() * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: markerColor.withOpacity(0.3),
                width: 2,
              ),
            ),
          ),

        // نقطه مرکزی (داخلی)
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: markerColor,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: markerColor.withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),

        // نشانگر بیرونی با آیکون
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: markerColor.withOpacity(0.2),
            border: Border.all(
              color: markerColor.withOpacity(0.5),
              width: 2,
            ),
          ),
          child: Icon(
            _getMarkerIcon(),
            color: markerColor,
            size: 22,
          ),
        ),

        // نوار اطمینان (بصری اضافی)
        if (confidence > 0)
          Positioned(
            bottom: -15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: markerColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(confidence * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// نشانگر انیمیشن‌دار (استفاده برای نمایش موقعیت‌های مختلف)
class AnimatedPositionMarker extends StatefulWidget {
  final EnvironmentType environmentType;
  final double confidence;
  final Duration animationDuration;

  const AnimatedPositionMarker({
    Key? key,
    this.environmentType = EnvironmentType.unknown,
    this.confidence = 0.5,
    this.animationDuration = const Duration(milliseconds: 800),
  }) : super(key: key);

  @override
  State<AnimatedPositionMarker> createState() => _AnimatedPositionMarkerState();
}

class _AnimatedPositionMarkerState extends State<AnimatedPositionMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: PositionMarker(
          environmentType: widget.environmentType,
          confidence: widget.confidence,
          showConfidenceRing: true,
        ),
      ),
    );
  }
}

/// نشانگر مرجع (برای موقعیت‌های شناخته‌شده در آموزش)
class ReferenceMarker extends StatelessWidget {
  final String label;
  final bool isSelected;

  const ReferenceMarker({
    Key? key,
    this.label = 'Ref',
    this.isSelected = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // حلقه بیرونی (اختیاری)
        if (isSelected)
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.yellow,
                width: 3,
              ),
            ),
          ),

        // نقطه مرجع
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.shade600,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              label.isNotEmpty ? label[0].toUpperCase() : 'R',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// نشانگر مسیر (برای نقاط تاریخچه)
class TrajectoryMarker extends StatelessWidget {
  final int index;
  final bool isLatest;

  const TrajectoryMarker({
    Key? key,
    this.index = 0,
    this.isLatest = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = isLatest ? 14.0 : 10.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLatest ? Colors.blue : Colors.blue.shade300,
        border: Border.all(
          color: Colors.white,
          width: 1,
        ),
      ),
      child: Center(
        child: isLatest
            ? const Icon(Icons.check, color: Colors.white, size: 8)
            : const SizedBox.shrink(),
      ),
    );
  }
}
