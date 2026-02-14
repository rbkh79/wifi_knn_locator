import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../data_model.dart';
import '../local_database.dart';

/// نوع محیط (Indoor/Outdoor/Hybrid/Unknown)
enum EnvironmentType { indoor, outdoor, hybrid, unknown }

/// پنل نمایش موقعیت تخمین‌زده‌شده با مختصات، اطمینان و عملیات
class PositionDisplayPanel extends StatefulWidget {
  final LocationEstimate? estimate;
  final EnvironmentType environmentType;
  final VoidCallback? onRefresh;
  final bool isLoading;

  const PositionDisplayPanel({
    Key? key,
    this.estimate,
    this.environmentType = EnvironmentType.unknown,
    this.onRefresh,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<PositionDisplayPanel> createState() => _PositionDisplayPanelState();
}

class _PositionDisplayPanelState extends State<PositionDisplayPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  bool _showSuccessAnimation = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  /// شروع انیمیشن لرزش (پانل)
  void _playShakeAnimation() {
    _shakeController.forward().then((_) {
      _shakeController.reset();
    });
  }

  /// شروع انیمیشن موفقیت
  void _playSuccessAnimation() {
    setState(() => _showSuccessAnimation = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showSuccessAnimation = false);
      }
    });
  }

  /// کپی کردن مختصات به کلیپ‌بورد
  Future<void> _copyCoordinates() async {
    if (widget.estimate == null) return;
    final coords =
        '${widget.estimate!.latitude.toStringAsFixed(6)},${widget.estimate!.longitude.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: coords));
    _playSuccessAnimation();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('مختصات کپی شد'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  /// اشتراک‌گذاری مختصات
  Future<void> _shareCoordinates() async {
    if (widget.estimate == null) return;
    final lat = widget.estimate!.latitude.toStringAsFixed(6);
    final lon = widget.estimate!.longitude.toStringAsFixed(6);
    final envType = _environmentTypeLabel();
    final conf = (widget.estimate!.confidence * 100).toStringAsFixed(0);
    final text = '''
موقعیت تخمین‌زده‌شده:
عرض جغرافیایی: $lat
طول جغرافیایی: $lon
اطمینان: $conf%
محیط: $envType

مختصات: $lat,$lon
''';
    await Share.share(text);
  }

  /// ذخیره موقعیت در history
  Future<void> _saveToHistory() async {
    if (widget.estimate == null) return;
    try {
      final db = LocalDatabase.instance;
      await db.insertLocationHistory(
        LocationHistoryEntry(
          deviceId: 'user-device',
          latitude: widget.estimate!.latitude,
          longitude: widget.estimate!.longitude,
          zoneLabel: widget.estimate!.zoneLabel ?? _environmentTypeLabel(),
          confidence: widget.estimate!.confidence,
          timestamp: DateTime.now(),
        ),
      );
      _playSuccessAnimation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('موقعیت ذخیره شد'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// برچسب نوع محیط
  String _environmentTypeLabel() {
    switch (widget.environmentType) {
      case EnvironmentType.indoor:
        return 'داخلی';
      case EnvironmentType.outdoor:
        return 'خارجی';
      case EnvironmentType.hybrid:
        return 'ترکیبی';
      case EnvironmentType.unknown:
      default:
        return 'ناشناخته';
    }
  }

  /// آیکون نوع محیط
  IconData _environmentTypeIcon() {
    switch (widget.environmentType) {
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

  /// رنگ نوع محیط
  Color _environmentTypeColor() {
    switch (widget.environmentType) {
      case EnvironmentType.indoor:
        return Colors.blue.shade400;
      case EnvironmentType.outdoor:
        return Colors.green.shade400;
      case EnvironmentType.hybrid:
        return Colors.purple.shade400;
      case EnvironmentType.unknown:
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDarkMode ? Colors.grey.shade900 : Colors.grey.shade50;
    final textColor = isDarkMode ? Colors.grey.shade100 : Colors.grey.shade900;

    if (widget.estimate == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.location_off, size: 32, color: Colors.grey.shade600),
            const SizedBox(height: 8),
            Text(
              'موقعیتی برای نمایش وجود ندارد',
              style: TextStyle(color: textColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (widget.onRefresh != null)
              ElevatedButton.icon(
                onPressed:
                    widget.isLoading ? null : widget.onRefresh,
                icon: widget.isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('اسکن مجدد'),
              ),
          ],
        ),
      );
    }

    final lat = widget.estimate!.latitude.toStringAsFixed(6);
    final lon = widget.estimate!.longitude.toStringAsFixed(6);
    final confidence = widget.estimate!.confidence;
    final confidencePercent = (confidence * 100).toStringAsFixed(0);

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticInOut)),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _environmentTypeColor().withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان
            Row(
              children: [
                Icon(Icons.location_on, color: _environmentTypeColor(), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'موقعیت تخمین‌زده‌شده',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_showSuccessAnimation)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ],
            ),
            const SizedBox(height: 12),

            // مختصات
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.grey.shade800
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'عرض جغرافیایی',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        lat + '°',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'طول جغرافیایی',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        lon + '°',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // اطمینان
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'اطمینان',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$confidencePercent%',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: confidence,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getConfidenceColor(confidence),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // نوع محیط
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _environmentTypeColor().withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(_environmentTypeIcon(), color: _environmentTypeColor(), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _environmentTypeLabel(),
                    style: TextStyle(
                      color: _environmentTypeColor(),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // دکمه‌ها
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.copy,
                  label: 'کپی',
                  onPressed: _copyCoordinates,
                ),
                _ActionButton(
                  icon: Icons.share,
                  label: 'اشتراک',
                  onPressed: _shareCoordinates,
                ),
                _ActionButton(
                  icon: Icons.save,
                  label: 'ذخیره',
                  onPressed: _saveToHistory,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.7) return Colors.green.shade400;
    if (confidence >= 0.5) return Colors.blue.shade400;
    if (confidence >= 0.3) return Colors.orange.shade400;
    return Colors.red.shade400;
  }
}

/// دکمه عملیات (کپی/اشتراک/ذخیره)
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
