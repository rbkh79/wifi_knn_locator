import 'package:flutter/material.dart';
import '../models/environment_type.dart';

/// هدر نمایش وضعیت اپراتور و سیگنال
class OperatorStatusHeader extends StatelessWidget {
  final String operatorName;
  final String networkType; // '4G', '5G', 'WiFi'
  final int signalStrength; // 0-100
  final EnvironmentType environmentType;
  final double batteryLevel; // 0-1
  final bool isCharging;

  const OperatorStatusHeader({
    Key? key,
    required this.operatorName,
    required this.networkType,
    required this.signalStrength,
    required this.environmentType,
    required this.batteryLevel,
    this.isCharging = false,
  }) : super(key: key);

  Color _getOperatorColor() {
    if (operatorName.contains('همراه')) return const Color(0xFF4CAF50);
    if (operatorName.contains('ایرانسل')) return const Color(0xFFFF9800);
    if (operatorName.contains('رایتل')) return const Color(0xFF2196F3);
    if (operatorName.contains('شاتل')) return const Color(0xFF9C27B0);
    return Colors.grey;
  }

  IconData _getOperatorIcon() {
    if (operatorName.contains('همراه')) return Icons.phone_android;
    if (operatorName.contains('ایرانسل')) return Icons.phone_iphone;
    if (operatorName.contains('رایتل')) return Icons.signal_cellular_alt;
    if (operatorName.contains('شاتل')) return Icons.wifi;
    return Icons.signal_cellular_null;
  }

  IconData _getEnvironmentIcon() {
    switch (environmentType) {
      case EnvironmentType.indoor:
        return Icons.home_work;
      case EnvironmentType.outdoor:
        return Icons.public;
      case EnvironmentType.hybrid:
        return Icons.merge_type;
      case EnvironmentType.unknown:
      default:
        return Icons.help_outline;
    }
  }

  String _getEnvironmentLabel() {
    switch (environmentType) {
      case EnvironmentType.indoor:
        return 'داخلی';
      case EnvironmentType.outdoor:
        return 'خارجی';
      case EnvironmentType.hybrid:
        return 'ترکیبی';
      case EnvironmentType.unknown:
      default:
        return 'نامشخص';
    }
  }

  Color _getSignalColor() {
    if (signalStrength >= 75) return Colors.green;
    if (signalStrength >= 50) return Colors.blue;
    if (signalStrength >= 25) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // اپراتور
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _getOperatorColor().withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _getOperatorIcon(),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          operatorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          networkType,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // سیگنال
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.signal_cellular_4_bar,
                    color: _getSignalColor(),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$signalStrength%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // محیط
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getEnvironmentIcon(),
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getEnvironmentLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // باتری
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 24,
                    height: 12,
                    child: CustomPaint(
                      painter: BatteryPainter(
                        level: batteryLevel,
                        isCharging: isCharging,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(batteryLevel * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom Painter برای رسم باتری
class BatteryPainter extends CustomPainter {
  final double level;
  final bool isCharging;

  BatteryPainter({required this.level, required this.isCharging});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _getLevelColor()
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // بدنه باتری
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * 0.85, size.height),
        const Radius.circular(2),
      ),
      borderPaint,
    );

    // سر باتری
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.85, size.height * 0.3, size.width * 0.15, size.height * 0.4),
      borderPaint,
    );

    // سطح شارژ
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, (size.width * 0.83 - 2) * level, size.height - 2),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  Color _getLevelColor() {
    if (isCharging) return Colors.green;
    if (level >= 0.5) return Colors.green;
    if (level >= 0.2) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(BatteryPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.isCharging != isCharging;
  }
}
