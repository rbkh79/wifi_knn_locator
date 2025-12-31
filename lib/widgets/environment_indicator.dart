/// ویجت نمایش وضعیت محیط (Indoor/Outdoor Indicator)
/// 
/// این ویجت وضعیت محیط فعلی کاربر را نمایش می‌دهد.
import 'package:flutter/material.dart';

/// ویجت نمایش وضعیت محیط
class EnvironmentIndicator extends StatelessWidget {
  final String environmentType; // 'indoor', 'outdoor', 'hybrid', 'unknown'
  final double confidence;

  const EnvironmentIndicator({
    Key? key,
    required this.environmentType,
    required this.confidence,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _getEnvironmentInfo();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (confidence > 0) ...[
            const SizedBox(width: 8),
            Text(
              '(${(confidence * 100).toStringAsFixed(0)}%)',
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (IconData, String, Color) _getEnvironmentInfo() {
    switch (environmentType) {
      case 'indoor':
        return (Icons.home, 'محیط بسته', Colors.blue);
      case 'outdoor':
        return (Icons.park, 'محیط باز', Colors.green);
      case 'hybrid':
        return (Icons.swap_horiz, 'ترکیبی', Colors.purple);
      default:
        return (Icons.help_outline, 'نامشخص', Colors.grey);
    }
  }
}

