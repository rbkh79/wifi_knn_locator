import 'package:flutter/material.dart';
import '../data_model.dart';
import '../models/environment_type.dart';

/// پنل مختصات جغرافیایی و اطلاعات پایین صفحه
class CoordinatePanel extends StatefulWidget {
  final LocationEstimate? estimate;
  final EnvironmentType environmentType;
  final String? operatorName;
  final bool isLoading;
  final VoidCallback? onScan;
  final VoidCallback? onSave;

  const CoordinatePanel({
    Key? key,
    this.estimate,
    this.environmentType = EnvironmentType.unknown,
    this.operatorName,
    this.isLoading = false,
    this.onScan,
    this.onSave,
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
      maxChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, -2),
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
              const SizedBox(height: 8),
              _buildCoordinateRow(
                context,
                'طول جغرافیایی',
                lon,
                '°E',
              ),
              const SizedBox(height: 16),

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
              const SizedBox(height: 16),

              // دکمه‌ها
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
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('اسکن مجدد'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.onSave,
                      icon: const Icon(Icons.save),
                      label: const Text('ذخیره'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
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
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, -2),
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
              // TODO: Copy to clipboard
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

  String _getEnvironmentLabel() {
    switch (widget.environmentType) {
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
