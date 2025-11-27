import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data_model.dart';
import '../wifi_scanner.dart';
import '../services/fingerprint_service.dart';
import '../services/auto_csv_service.dart';
import '../services/location_service.dart';
import '../config.dart';

/// مدل نقطه مرجع روی نقشه
class ReferencePoint {
  final int index; // 0 تا 24
  final double x; // مختصات x به متر (نسبت به مبدأ)
  final double y; // مختصات y به متر (نسبت به مبدأ)
  final LatLng position; // موقعیت جغرافیایی
  bool isRecorded; // آیا RSSI ثبت شده است؟
  WifiScanResult? scanResult; // نتیجه اسکن Wi-Fi

  ReferencePoint({
    required this.index,
    required this.x,
    required this.y,
    required this.position,
    this.isRecorded = false,
    this.scanResult,
  });
}

/// صفحه انتخاب نقطه مبدأ و تولید 25 نقطه مرجع
class MapReferencePointPicker extends StatefulWidget {
  final FingerprintService fingerprintService;
  final String? sessionId;
  final String? contextId;

  const MapReferencePointPicker({
    Key? key,
    required this.fingerprintService,
    this.sessionId,
    this.contextId,
  }) : super(key: key);

  @override
  State<MapReferencePointPicker> createState() => _MapReferencePointPickerState();
}

class _MapReferencePointPickerState extends State<MapReferencePointPicker> {
  // کنترلر نقشه
  final MapController _mapController = MapController();
  
  // نقطه مبدأ (مرکز) - مختصات جغرافیایی
  LatLng? _originPoint;
  
  // لیست 25 نقطه مرجع
  List<ReferencePoint> _referencePoints = [];
  
  // فاصله بین نقاط (به متر)
  double _stepSize = 0.5; // متر
  
  // نقطه انتخاب شده برای ثبت RSSI
  ReferencePoint? _selectedPoint;
  
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isLocating = false;
  
  // کنترلر برای تنظیم فاصله بین نقاط
  final TextEditingController _stepSizeController = TextEditingController(text: '0.5');

  @override
  void initState() {
    super.initState();
    _stepSizeController.addListener(() {
      final value = double.tryParse(_stepSizeController.text);
      if (value != null && value > 0 && value <= 2.0) {
        setState(() {
          _stepSize = value;
          // بازسازی نقاط با فاصله جدید
          if (_originPoint != null) {
            _generateReferencePoints();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _stepSizeController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// تبدیل متر به درجه جغرافیایی
  /// تقریباً: 1 درجه عرض جغرافیایی ≈ 111320 متر
  LatLng _meterToLatLng(LatLng origin, double xMeters, double yMeters) {
    // تبدیل x (شرق-غرب) به longitude
    final latRad = origin.latitude * math.pi / 180;
    final lonDegrees = xMeters / (111320.0 * math.cos(latRad));
    
    // تبدیل y (شمال-جنوب) به latitude
    final latDegrees = yMeters / 111320.0;
    
    return LatLng(
      origin.latitude + latDegrees,
      origin.longitude + lonDegrees,
    );
  }

  /// تولید 25 نقطه مرجع حول نقطه مبدأ
  void _generateReferencePoints() {
    if (_originPoint == null) return;
    
    final points = <ReferencePoint>[];
    
    // نقطه 0: همان نقطه مبدأ
    points.add(ReferencePoint(
      index: 0,
      x: 0.0,
      y: 0.0,
      position: _originPoint!,
    ));
    
    // تولید 24 نقطه دیگر در شبکه 5×5
    int pointIndex = 1;
    for (int i = -2; i <= 2; i++) {
      for (int j = -2; j <= 2; j++) {
        // رد کردن نقطه مرکز (که قبلاً اضافه شده)
        if (i == 0 && j == 0) continue;
        
        // محاسبه مختصات فیزیکی (به متر)
        final xMeters = i * _stepSize;
        final yMeters = j * _stepSize;
        
        // تبدیل به مختصات جغرافیایی
        final position = _meterToLatLng(_originPoint!, xMeters, yMeters);
        
        points.add(ReferencePoint(
          index: pointIndex++,
          x: xMeters,
          y: yMeters,
          position: position,
        ));
      }
    }
    
    setState(() {
      _referencePoints = points;
      _selectedPoint = null;
    });
  }

  /// مدیریت کلیک روی نقشه
  void _handleMapTap(LatLng point) {
    setState(() {
      _originPoint = point;
      _selectedPoint = null;
    });
    
    // حرکت نقشه به نقطه انتخاب شده
    _mapController.move(point, _mapController.camera.zoom);
    
    // تولید نقاط مرجع
    _generateReferencePoints();
  }

  /// استفاده از موقعیت فعلی دستگاه به عنوان مبدأ
  Future<void> _useCurrentLocationAsOrigin() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _selectedPoint = null;
    });

    try {
      final position = await LocationService.getCurrentPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('دسترسی به موقعیت امکان‌پذیر نیست. لطفاً GPS و مجوزها را بررسی کنید.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final newOrigin = LatLng(position.latitude, position.longitude);
      setState(() {
        _originPoint = newOrigin;
      });

      _mapController.move(newOrigin, math.max(_mapController.camera.zoom, 18));
      _generateReferencePoints();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('موقعیت فعلی به عنوان نقطه مبدأ تنظیم شد.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دریافت موقعیت: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  /// انتخاب یک نقطه برای ثبت RSSI
  void _selectPoint(ReferencePoint point) {
    setState(() {
      _selectedPoint = point;
    });
    
    // حرکت نقشه به نقطه انتخاب شده
    _mapController.move(point.position, _mapController.camera.zoom);
  }

  /// ثبت RSSI برای نقطه انتخاب شده
  Future<void> _recordRssiForPoint() async {
    if (_selectedPoint == null) return;
    if (widget.sessionId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('برای ثبت RSSI، ابتدا جلسه آموزش را در صفحه اصلی شروع کنید.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    setState(() {
      _isScanning = true;
    });
    
    try {
      // انجام اسکن Wi-Fi
      final scanResult = await WifiScanner.performScan();
      
      // استفاده از مختصات فیزیکی به عنوان zoneLabel
      final zoneLabel = 'MapRef_${_selectedPoint!.index}_X${_selectedPoint!.x.toStringAsFixed(2)}_Y${_selectedPoint!.y.toStringAsFixed(2)}';
      
      // ذخیره در پایگاه داده
      await widget.fingerprintService.saveFingerprint(
        latitude: _selectedPoint!.position.latitude,
        longitude: _selectedPoint!.position.longitude,
        zoneLabel: zoneLabel,
        scanResult: scanResult,
        sessionId: widget.sessionId,
        contextId: widget.contextId,
      );
      
      // ذخیره در CSV خودکار
      await AutoCsvService.addScan(
        scanResult: scanResult,
        latitude: _selectedPoint!.position.latitude,
        longitude: _selectedPoint!.position.longitude,
        zoneLabel: zoneLabel,
      );
      
      // به‌روزرسانی نقطه
      setState(() {
        _selectedPoint!.isRecorded = true;
        _selectedPoint!.scanResult = scanResult;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RSSI برای نقطه ${_selectedPoint!.index} ثبت شد! (${scanResult.accessPoints.length} AP)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ثبت RSSI: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// ساخت Marker برای نقاط مرجع
  List<Marker> _buildReferenceMarkers() {
    return _referencePoints.map((point) {
      Color markerColor;
      IconData iconData;
      double iconSize;
      
      if (point.index == 0) {
        // نقطه مبدأ
        markerColor = Colors.red;
        iconData = Icons.center_focus_strong;
        iconSize = 28;
      } else if (point.isRecorded) {
        // نقطه ثبت شده
        markerColor = Colors.green;
        iconData = Icons.check_circle;
        iconSize = 24;
      } else if (point == _selectedPoint) {
        // نقطه انتخاب شده
        markerColor = Colors.blue;
        iconData = Icons.radio_button_checked;
        iconSize = 28;
      } else {
        // نقطه ثبت نشده
        markerColor = Colors.orange;
        iconData = Icons.place;
        iconSize = 20;
      }
      
      return Marker(
        point: point.position,
        width: iconSize + 8,
        height: iconSize + 8,
        child: GestureDetector(
          onTap: () => _selectPoint(point),
          child: Container(
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              iconData,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('انتخاب نقطه مرجع روی نقشه'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Column(
        children: [
          // کنترل‌ها
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                if (widget.sessionId == null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هیچ جلسه فعالی از صفحه اصلی انتخاب نشده است. لطفاً به صفحه اصلی بازگردید و جلسه جدید بسازید.',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // راهنما
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'روی نقشه کلیک کنید تا نقطه مبدأ انتخاب شود. سپس 25 نقطه مرجع به صورت خودکار ایجاد می‌شود.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLocating ? null : _useCurrentLocationAsOrigin,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(_isLocating
                        ? 'در حال دریافت موقعیت...'
                        : 'استفاده از موقعیت فعلی به عنوان مبدأ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // تنظیم فاصله بین نقاط
                Row(
                  children: [
                    const Text('فاصله بین نقاط (متر):'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _stepSizeController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_selectedPoint != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نقطه انتخاب شده: ${_selectedPoint!.index}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('X: ${_selectedPoint!.x.toStringAsFixed(2)} متر'),
                        Text('Y: ${_selectedPoint!.y.toStringAsFixed(2)} متر'),
                        Text('وضعیت: ${_selectedPoint!.isRecorded ? "ثبت شده" : "ثبت نشده"}'),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isScanning ? null : _recordRssiForPoint,
                            icon: _isScanning
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isScanning ? 'در حال اسکن...' : 'ثبت RSSI در اینجا'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_referencePoints.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildLegendItem(Colors.red, 'مبدأ'),
                        _buildLegendItem(Colors.orange, 'ثبت نشده'),
                        _buildLegendItem(Colors.blue, 'انتخاب شده'),
                        _buildLegendItem(Colors.green, 'ثبت شده'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // نمایش نقشه
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude),
                initialZoom: AppConfig.defaultMapZoom,
                minZoom: AppConfig.minMapZoom,
                maxZoom: AppConfig.maxMapZoom,
                onTap: (tapPosition, point) {
                  _handleMapTap(point);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.wifi_knn_locator',
                ),
                if (_referencePoints.isNotEmpty)
                  MarkerLayer(markers: _buildReferenceMarkers()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
