import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../data_model.dart';
import '../models/environment_type.dart';
import '../config.dart';

/// پنل مختصات جغرافیایی و اطلاعات پایین صفحه
class CoordinatePanel extends StatefulWidget {
  final LocationEstimate? estimate;
  final EnvironmentType environmentType;
  final String? operatorName;
  final bool isLoading;
  final VoidCallback? onScan;
  final VoidCallback? onSave;
  final bool researchMode;
  final int? scanLatencyMs;
  final int? signalCount;
  final int kUsed;

  const CoordinatePanel({
    Key? key,
    this.estimate,
    this.environmentType = EnvironmentType.unknown,
    this.operatorName,
    this.isLoading = false,
    this.onScan,
    this.onSave,
    this.researchMode = false,
    this.scanLatencyMs,
    this.signalCount,
    this.kUsed = AppConfig.defaultK,
  }) : super(key: key);

  @override
  State<CoordinatePanel> createState() => _CoordinatePanelState();
}

class _CoordinatePanelState extends State<CoordinatePanel> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.estimate == null) {
      return _buildEmptyState();
    }

    final lat = widget.estimate!.latitude.toStringAsFixed(6);
    final lon = widget.estimate!.longitude.toStringAsFixed(6);
    final confidence = widget.estimate!.confidence;
    final confidencePercent = (confidence * 100).toStringAsFixed(0);

    return DraggableScrollableSheet(
      initialChildSize: 0.25,
      minChildSize: 0.15,
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              // گیره بالا
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // عنوان
              Text(
                'مختصات موقعیت',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              // مختصات
              _buildCoordinateRow(
                context,
                'عرض جغرافیایی',
                lat,
                '°N',
              ),
              const SizedBox(height: 4),
              _buildCoordinateRow(
                context,
                'طول جغرافیایی',
                lon,
                '°E',
              ),
              const SizedBox(height: 12),

              // دکمه‌های کپی و اشتراک
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'کپی مختصات',
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '$lat,$lon'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('مختصات کپی شد')),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'اشتراک مختصات',
                    icon: const Icon(Icons.share, size: 20),
                    onPressed: () {
                      Share.share('موقعیت من: $lat, $lon');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // اطمینان
              _buildConfidenceBar(confidencePercent, confidence),
              const SizedBox(height: 12),

              // اطلاعات اضافی
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoTag(
                    icon: Icons.public,
                    label: _getEnvironmentLabel(),
                    color: _getEnvironmentColor(),
                  ),
                  if (widget.operatorName != null)
                    _buildInfoTag(
                      icon: Icons.phone_android,
                      label: widget.operatorName!,
                      color: _getOperatorColor(),
                    ),
                ],
              ),
              if (widget.researchMode) ...[
                const SizedBox(height: 12),
                Text('🔧 Advanced metrics', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (widget.scanLatencyMs != null)
                      _buildMetric('Latency', '${widget.scanLatencyMs}ms'),
                    if (widget.signalCount != null)
                      _buildMetric('Signals', '${widget.signalCount}'),
                    _buildMetric('K', '${widget.kUsed}'),
                    _buildMetric('Conf', '$confidencePercent%'),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // دکمه‌های عملیاتی
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.isLoading ? null : widget.onScan,
                      icon: widget.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('اسکن'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onSave,
                      icon: const Icon(Icons.save),
                      label: const Text('ذخیره'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return DraggableScrollableSheet(
      initialChildSize: 0.25,
      minChildSize: 0.15,
      maxChildSize: 0.5,
      builder: (context, scrollController) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 32,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'موقعیتی برای نمایش وجود ندارد',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.isLoading ? null : widget.onScan,
                icon: const Icon(Icons.refresh),
                label: const Text('شروع اسکن'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoordinateRow(
    BuildContext context,
    String label,
    String value,
    String unit,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      unit,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              final text = '$value$unit';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ $text \u0628\u0647 clipboard \u06a9\u067e\u06cc \u0634\u062f'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            tooltip: 'کپی کردن',
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBar(String percent, double confidence) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'اعتماد به موقعیت',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              '$percent%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getConfidenceColor(confidence),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
    );
  }

  Widget _buildInfoTag({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  String _getEnvironmentLabel() {
    switch (widget.environmentType) {
      case EnvironmentType.indoor:
        return 'داخلی (فقط وای‌فای)';
      case EnvironmentType.hybrid:
        return 'داخلی (وای‌فای + BTS)';
      case EnvironmentType.outdoor:
        return 'خارجی (فقط BTS)';
      case EnvironmentType.unknown:
      default:
        return 'نامشخص';
    }
  }

  Color _getEnvironmentColor() {
    switch (widget.environmentType) {
      case EnvironmentType.indoor:
        return Colors.blue;
      case EnvironmentType.outdoor:
        return Colors.green;
      case EnvironmentType.hybrid:
        return Colors.purple;
      case EnvironmentType.unknown:
      default:
        return Colors.grey;
    }
  }

  Color _getOperatorColor() {
    if (widget.operatorName == null) return Colors.grey;
    if (widget.operatorName!.contains('همراه')) return Colors.green;
    if (widget.operatorName!.contains('ایرانسل')) return Colors.orange;
    if (widget.operatorName!.contains('رایتل')) return Colors.blue;
    if (widget.operatorName!.contains('شاتل')) return Colors.purple;
    return Colors.grey;
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.7) return Colors.green;
    if (confidence >= 0.5) return Colors.blue;
    if (confidence >= 0.3) return Colors.orange;
    return Colors.red;
  }
}
