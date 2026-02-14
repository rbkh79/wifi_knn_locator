import 'package:flutter/material.dart';

/// کلاس‌های انیمیشن برای نمایش بصری موقعیت و اسکن
class PositionAnimations {
  /// انیمیشن رادار پالس‌زن (هنگام اسکن)
  static Widget buildRadarAnimation({
    required AnimationController controller,
    required Color color,
    required double radius,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // حلقه اول (بیشتر کشیده)
            Container(
              width: radius * (0.5 + controller.value * 0.5),
              height: radius * (0.5 + controller.value * 0.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity((1 - controller.value) * 0.5),
                  width: 2,
                ),
              ),
            ),
            // حلقه دوم
            Container(
              width: radius * (0.3 + controller.value * 0.3),
              height: radius * (0.3 + controller.value * 0.3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity((1 - controller.value) * 0.7),
                  width: 1.5,
                ),
              ),
            ),
            // نقطه مرکزی
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// انیمیشن موج/پالس
  static Widget buildPulseAnimation({
    required AnimationController controller,
    required Color color,
    required double radius,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          width: radius * 2 * controller.value,
          height: radius * 2 * controller.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity((1 - controller.value) * 0.8),
              width: 2,
            ),
          ),
        );
      },
    );
  }

  /// انیمیشن لرزش پنل (برای عدم قطعیت بالا)
  static Animation<Offset> buildShakeAnimation(AnimationController controller) {
    return Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: controller, curve: _ShakeCurve()),
    );
  }

  /// انیمیشن زوم ورود
  static Animation<double> buildZoomInAnimation(AnimationController controller) {
    return Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.elasticOut),
    );
  }

  /// انیمیشن زوم خروج
  static Animation<double> buildZoomOutAnimation(AnimationController controller) {
    return Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeIn),
    );
  }

  /// انیمیشن محو شدن تدریجی
  static Animation<double> buildFadeAnimation(AnimationController controller) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
  }

  /// انیمیشن اسلاید (حرکت جانبی)
  static Animation<Offset> buildSlideAnimation(
    AnimationController controller, {
    Offset begin = const Offset(-1, 0),
    Offset end = Offset.zero,
  }) {
    return Tween<Offset>(begin: begin, end: end).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    );
  }

  /// انیمیشن چرخش
  static Animation<double> buildRotateAnimation(AnimationController controller) {
    return Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: controller, curve: Curves.linear),
    );
  }
}

/// منحنی سفارشی برای انیمیشن لرزش
class _ShakeCurve extends Curve {
  @override
  double transformInternal(double t) {
    // شش بار لرزش
    const int shakesCount = 6;
    final double shakesFraction = t * shakesCount;
    final double mod = shakesFraction % 1;
    final double amplitude = (1 - shakesFraction).clamp(0, 1);
    return (mod > 0.5) ? amplitude * 0.05 : -amplitude * 0.05;
  }
}

/// ویجت انیمیشن رادار
class RadarAnimationWidget extends StatefulWidget {
  final Color color;
  final double radius;
  final Duration duration;
  final bool isActive;

  const RadarAnimationWidget({
    Key? key,
    required this.color,
    this.radius = 50,
    this.duration = const Duration(milliseconds: 1500),
    this.isActive = false,
  }) : super(key: key);

  @override
  State<RadarAnimationWidget> createState() => _RadarAnimationWidgetState();
}

class _RadarAnimationWidgetState extends State<RadarAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RadarAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PositionAnimations.buildRadarAnimation(
      controller: _controller,
      color: widget.color,
      radius: widget.radius,
    );
  }
}

/// ویجت انیمیشن پالس
class PulseAnimationWidget extends StatefulWidget {
  final Color color;
  final double radius;
  final Duration duration;
  final bool isActive;

  const PulseAnimationWidget({
    Key? key,
    required this.color,
    this.radius = 30,
    this.duration = const Duration(milliseconds: 1500),
    this.isActive = false,
  }) : super(key: key);

  @override
  State<PulseAnimationWidget> createState() => _PulseAnimationWidgetState();
}

class _PulseAnimationWidgetState extends State<PulseAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulseAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PositionAnimations.buildPulseAnimation(
      controller: _controller,
      color: widget.color,
      radius: widget.radius,
    );
  }
}

/// ویجت نوار پیشرفت انیمیشن‌دار برای اطمینان
class AnimatedConfidenceBar extends StatefulWidget {
  final double confidence;
  final Duration duration;

  const AnimatedConfidenceBar({
    Key? key,
    required this.confidence,
    this.duration = const Duration(milliseconds: 800),
  }) : super(key: key);

  @override
  State<AnimatedConfidenceBar> createState() => _AnimatedConfidenceBarState();
}

class _AnimatedConfidenceBarState extends State<AnimatedConfidenceBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: widget.confidence).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedConfidenceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.confidence != widget.confidence) {
      _animation = Tween<double>(begin: _animation.value, end: widget.confidence)
          .animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getColor(double value) {
    if (value >= 0.7) return Colors.green;
    if (value >= 0.5) return Colors.blue;
    if (value >= 0.3) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'اطمینان',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${(_animation.value * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getColor(_animation.value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _animation.value,
                minHeight: 6,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getColor(_animation.value),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// ویجت انیمیشن علامت موفقیت
class SuccessCheckAnimation extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onComplete;

  const SuccessCheckAnimation({
    Key? key,
    this.duration = const Duration(milliseconds: 1500),
    this.onComplete,
  }) : super(key: key);

  @override
  State<SuccessCheckAnimation> createState() => _SuccessCheckAnimationState();
}

class _SuccessCheckAnimationState extends State<SuccessCheckAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green.shade400,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 28),
      ),
    );
  }
}
