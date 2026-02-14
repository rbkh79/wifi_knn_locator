import 'package:flutter/material.dart';
import '../data_model.dart';
import '../widgets/position_marker.dart';
import '../widgets/position_display_panel.dart';
import '../utils/position_animations.dart';
import '../services/map_controller_service.dart';

/// صفحه نمایشی برای تمام ویژگی‌های موقعیت
/// این صفحه تمام انیمیشن‌ها، نشانگرها و عملیات موقعیت را نمایش می‌دهد
class PositionShowcaseScreen extends StatefulWidget {
  const PositionShowcaseScreen({Key? key}) : super(key: key);

  @override
  State<PositionShowcaseScreen> createState() => _PositionShowcaseScreenState();
}

class _PositionShowcaseScreenState extends State<PositionShowcaseScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  late AnimationController _pulseController;
  late AnimationController _zoomController;

  // نمونه موقعیت
  late LocationEstimate _samplePosition;
  double _confidence = 0.75;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    
    // ایجاد animation controllers
    _radarController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _zoomController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // نمونه موقعیت (تهران - میدان آزادی)
    _samplePosition = LocationEstimate(
      latitude: 35.7961,
      longitude: 51.3878,
      confidence: _confidence,
      zoneLabel: 'میدان آزادی',
      nearestNeighbors: 5,
      averageDistance: 42.3,
    );
  }

  @override
  void dispose() {
    _radarController.dispose();
    _pulseController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  /// شبیه‌سازی اسکن
  void _simulateScan() {
    setState(() => _isScanning = true);
    
    // شروع رادار
    _radarController.repeat();
    
    // شروع پالس
    _pulseController.repeat(reverse: true);
    
    // شبیه‌سازی مدت زمان اسکن
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _radarController.stop();
        _pulseController.stop();
        _zoomController.forward();
        
        // به‌روزرسانی اطمینان
        setState(() {
          _confidence = 0.85;
          _samplePosition = LocationEstimate(
            latitude: 35.7961 + (0.001 * (0.5 - 0.5)),
            longitude: 51.3878 + (0.001 * (0.5 - 0.5)),
            confidence: _confidence,
            zoneLabel: 'میدان آزادی',
            nearestNeighbors: 5,
            averageDistance: 32.1,
          );
          _isScanning = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نمایش موقعیت‌یابی'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بخش 1: نشانگرهای مختلف
          Text(
            'نشانگرهای موقعیت',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 32,
                runSpacing: 32,
                alignment: WrapAlignment.center,
                children: [
                  Column(
                    children: [
                      PositionMarker(
                        environmentType: EnvironmentType.indoor,
                        confidence: 0.8,
                      ),
                      const SizedBox(height: 8),
                      const Text('داخلی (Indoor)'),
                    ],
                  ),
                  Column(
                    children: [
                      PositionMarker(
                        environmentType: EnvironmentType.outdoor,
                        confidence: 0.6,
                      ),
                      const SizedBox(height: 8),
                      const Text('خارجی (Outdoor)'),
                    ],
                  ),
                  Column(
                    children: [
                      PositionMarker(
                        environmentType: EnvironmentType.hybrid,
                        confidence: 0.9,
                      ),
                      const SizedBox(height: 8),
                      const Text('ترکیبی (Hybrid)'),
                    ],
                  ),
                  Column(
                    children: [
                      PositionMarker(
                        environmentType: EnvironmentType.unknown,
                        confidence: 0.3,
                      ),
                      const SizedBox(height: 8),
                      const Text('نامشخص (Unknown)'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // بخش 2: انیمیشن‌های حین اسکن
          Text(
            'انیمیشن‌های حین اسکن',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // رادار
                  SizedBox(
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        RadarAnimationWidget(
                          color: Colors.blue,
                          radius: 60,
                          isActive: _isScanning,
                        ),
                        if (_isScanning)
                          const Icon(
                            Icons.wifi,
                            size: 32,
                            color: Colors.blue,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isScanning ? 'در حال اسکن...' : 'رادار آماده است',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // بخش 3: نوار اطمینان انیمیشن‌دار
          Text(
            'اطمینان نسبت به موقعیت',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AnimatedConfidenceBar(
                    confidence: _confidence,
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _confidence,
                    onChanged: (value) {
                      setState(() => _confidence = value);
                    },
                    divisions: 10,
                    label: '${(_confidence * 100).toStringAsFixed(0)}%',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'لغزش برای تغییر اطمینان',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // بخش 4: پنل نمایش موقعیت
          Text(
            'پنل نمایش مختصات',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          PositionDisplayPanel(
            estimate: _samplePosition,
            environmentType: EnvironmentType.indoor,
            onRefresh: _simulateScan,
            isLoading: _isScanning,
          ),
          const SizedBox(height: 24),

          // بخش 5: دکمه شروع اسکن
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _simulateScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.radar),
                    label: Text(_isScanning ? 'در حال اسکن...' : 'شروع اسکن'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isScanning
                        ? 'لطفاً صبر کنید. اسکن در حال انجام است...'
                        : 'برای مشاهده انیمیشن‌های اسکن و موقعیت، دکمه را فشار دهید',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // بخش 6: مرجع‌های عملی
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نکات فنی',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    '📍 نشانگرها',
                    'رنگ نشانگر بر اساس نوع محیط (داخلی/خارجی/ترکیبی) تغییر می‌یابد\n'
                        'شعاع حلقه اطمینان متناسب با میزان عدم قطعیت است',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoItem(
                    '📡 رادار',
                    'هنگام اسکن، دو حلقه رادار به صورت انیمیشن نمایش داده می‌شود\n'
                        'سرعت انیمیشن را می‌توان تنظیم کرد',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoItem(
                    '📊 اطمینان',
                    'نوار پیشرفت رنگین اطمینان را نمایش می‌دهد\n'
                        'سبز: بالا (>70%) | آبی: متوسط | نارنجی: پایین | قرمز: خیلی پایین',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoItem(
                    '💾 ذخیره‌سازی',
                    'موقعیت‌ها خودکار در جدول location_history ذخیره می‌شوند\n'
                        'تاریخچه را می‌توان مشاهده و صادر کرد',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
