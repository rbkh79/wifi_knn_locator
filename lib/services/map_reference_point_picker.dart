import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math' as math;
import '../data_model.dart';
import '../local_database.dart';
import '../wifi_scanner.dart';
import '../services/fingerprint_service.dart';
import '../services/auto_csv_service.dart';
import '../utils/privacy_utils.dart';

/// مدل نقطه مرجع روی نقشه
class ReferencePoint {
  final int index; // 0 تا 24
  final double x; // مختصات x به متر
  final double y; // مختصات y به متر
  final Offset pixelPosition; // موقعیت پیکسلی روی تصویر
  bool isRecorded; // آیا RSSI ثبت شده است؟
  WifiScanResult? scanResult; // نتیجه اسکن Wi-Fi

  ReferencePoint({
    required this.index,
    required this.x,
    required this.y,
    required this.pixelPosition,
    this.isRecorded = false,
    this.scanResult,
  });
}

/// صفحه انتخاب نقطه مبدأ و تولید 25 نقطه مرجع
class MapReferencePointPicker extends StatefulWidget {
  final FingerprintService fingerprintService;
  final LocalDatabase database;

  const MapReferencePointPicker({
    Key? key,
    required this.fingerprintService,
    required this.database,
  }) : super(key: key);

  @override
  State<MapReferencePointPicker> createState() => _MapReferencePointPickerState();
}

class _MapReferencePointPickerState extends State<MapReferencePointPicker> {
  // تصویر نقشه
  File? _mapImageFile;
  XFile? _selectedImage;
  ImageProvider? _mapImageProvider;
  
  // نقطه مبدأ (مرکز)
  Offset? _originPoint;
  double _originX = 0.0; // متر
  double _originY = 0.0; // متر
  
  // لیست 25 نقطه مرجع
  List<ReferencePoint> _referencePoints = [];
  
  // ضریب مقیاس‌دهی (پیکسل به متر)
  double _scaleFactor = 50.0; // هر 50 پیکسل = 1 متر (قابل تنظیم)
  
  // اندازه تصویر نقشه
  Size? _imageSize;
  
  // نقطه انتخاب شده برای ثبت RSSI
  ReferencePoint? _selectedPoint;
  
  bool _isLoading = false;
  bool _isScanning = false;
  
  // کنترلر برای تنظیم ضریب مقیاس
  final TextEditingController _scaleController = TextEditingController(text: '50.0');
  
  // GlobalKey برای دسترسی به موقعیت تصویر
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scaleController.addListener(() {
      final value = double.tryParse(_scaleController.text);
      if (value != null && value > 0) {
        setState(() {
          _scaleFactor = value;
          // بازسازی نقاط با ضریب جدید
          if (_originPoint != null) {
            _generateReferencePoints();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  /// انتخاب تصویر نقشه
  Future<void> _pickMapImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _mapImageFile = File(image.path);
          _mapImageProvider = FileImage(_mapImageFile!);
          _originPoint = null;
          _referencePoints = [];
          _selectedPoint = null;
        });
        
        // دریافت اندازه تصویر
        _loadImageSize();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در انتخاب تصویر: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// دریافت اندازه تصویر
  Future<void> _loadImageSize() async {
    if (_mapImageFile == null) return;
    
    final image = await _mapImageFile!.readAsBytes();
    final codec = await PaintingBinding.instance.instantiateImageCodec(image);
    final frame = await codec.getNextFrame();
    
    setState(() {
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
    });
  }

  /// تبدیل پیکسل به متر
  double _pixelToMeter(double pixels) {
    return pixels / _scaleFactor;
  }

  /// تبدیل متر به پیکسل
  double _meterToPixel(double meters) {
    return meters * _scaleFactor;
  }

  /// تبدیل مختصات پیکسلی به مختصات فیزیکی (متر)
  Offset _pixelToPhysical(Offset pixelPos) {
    if (_imageSize == null || _originPoint == null) {
      return Offset.zero;
    }
    
    // محاسبه فاصله از نقطه مبدأ (به پیکسل)
    final dx = pixelPos.dx - _originPoint!.dx;
    final dy = pixelPos.dy - _originPoint!.dy;
    
    // تبدیل به متر
    final xMeters = _pixelToMeter(dx);
    final yMeters = _pixelToMeter(-dy); // معکوس کردن y (چون در تصویر y به پایین است)
    
    return Offset(xMeters, yMeters);
  }

  /// تولید 25 نقطه مرجع حول نقطه مبدأ
  void _generateReferencePoints() {
    if (_originPoint == null || _imageSize == null) return;
    
    final points = <ReferencePoint>[];
    
    // نقطه 0: همان نقطه مبدأ
    points.add(ReferencePoint(
      index: 0,
      x: 0.0,
      y: 0.0,
      pixelPosition: _originPoint!,
    ));
    
    // تولید 24 نقطه دیگر در شبکه 5×5
    // فاصله بین نقاط: 0.5 تا 1.5 متر
    final gridSize = 5;
    final stepSize = 0.5; // متر
    
    int pointIndex = 1;
    for (int i = -2; i <= 2; i++) {
      for (int j = -2; j <= 2; j++) {
        // رد کردن نقطه مرکز (که قبلاً اضافه شده)
        if (i == 0 && j == 0) continue;
        
        // محاسبه مختصات فیزیکی
        final xMeters = i * stepSize;
        final yMeters = j * stepSize;
        
        // تبدیل به پیکسل
        final dxPixels = _meterToPixel(xMeters);
        final dyPixels = _meterToPixel(yMeters);
        
        final pixelPos = Offset(
          _originPoint!.dx + dxPixels,
          _originPoint!.dy - dyPixels, // معکوس کردن y
        );
        
        // بررسی اینکه نقطه در محدوده تصویر باشد
        if (pixelPos.dx >= 0 && pixelPos.dx <= _imageSize!.width &&
            pixelPos.dy >= 0 && pixelPos.dy <= _imageSize!.height) {
          points.add(ReferencePoint(
            index: pointIndex++,
            x: xMeters,
            y: yMeters,
            pixelPosition: pixelPos,
          ));
        }
      }
    }
    
    setState(() {
      _referencePoints = points;
    });
  }

  /// مدیریت کلیک روی تصویر نقشه
  void _handleImageTap(TapDownDetails details, Size imageDisplaySize) {
    if (_mapImageFile == null || _imageSize == null) return;
    
    // پیدا کردن موقعیت تصویر در صفحه
    final imageBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox == null) return;
    
    final localPosition = imageBox.globalToLocal(details.globalPosition);
    
    // تبدیل به مختصات واقعی تصویر (با در نظر گیری scale)
    // تصویر ممکن است با fit: BoxFit.contain نمایش داده شود
    final imageAspectRatio = _imageSize!.width / _imageSize!.height;
    final displayAspectRatio = imageDisplaySize.width / imageDisplaySize.height;
    
    double scaleX, scaleY;
    double offsetX = 0, offsetY = 0;
    
    if (imageAspectRatio > displayAspectRatio) {
      // تصویر عرض بیشتری دارد - scale بر اساس عرض
      scaleX = scaleY = _imageSize!.width / imageDisplaySize.width;
      offsetY = (imageDisplaySize.height - _imageSize!.height / scaleX) / 2;
    } else {
      // تصویر ارتفاع بیشتری دارد - scale بر اساس ارتفاع
      scaleX = scaleY = _imageSize!.height / imageDisplaySize.height;
      offsetX = (imageDisplaySize.width - _imageSize!.width / scaleY) / 2;
    }
    
    // محاسبه موقعیت کلیک در مختصات تصویر
    final imageX = (localPosition.dx - offsetX) * scaleX;
    final imageY = (localPosition.dy - offsetY) * scaleY;
    
    // بررسی اینکه آیا در محدوده تصویر هستیم
    if (imageX < 0 || imageX > _imageSize!.width ||
        imageY < 0 || imageY > _imageSize!.height) {
      return;
    }
    
    final tapPosition = Offset(imageX, imageY);
    
    // بررسی اینکه آیا روی یکی از نقاط مرجع کلیک شده
    for (final point in _referencePoints) {
      final distance = (tapPosition - point.pixelPosition).distance;
      if (distance < 20) { // 20 پیکسل tolerance
        _selectPoint(point);
        return;
      }
    }
    
    // اگر روی نقطه مرجع کلیک نشده، نقطه مبدأ جدید تنظیم می‌شود
    setState(() {
      _originPoint = tapPosition;
      _originX = 0.0;
      _originY = 0.0;
      _selectedPoint = null;
    });
    
    _generateReferencePoints();
  }

  /// انتخاب یک نقطه برای ثبت RSSI
  void _selectPoint(ReferencePoint point) {
    setState(() {
      _selectedPoint = point;
    });
  }

  /// ثبت RSSI برای نقطه انتخاب شده
  Future<void> _recordRssiForPoint() async {
    if (_selectedPoint == null) return;
    
    setState(() {
      _isScanning = true;
    });
    
    try {
      // انجام اسکن Wi-Fi
      final scanResult = await WifiScanner.performScan();
      
      // ذخیره در پایگاه داده
      // برای ذخیره، باید مختصات جغرافیایی داشته باشیم
      // اما چون ما مختصات فیزیکی (x, y) داریم، باید آن‌ها را به عنوان zoneLabel ذخیره کنیم
      // یا می‌توانیم یک سیستم مختصات محلی تعریف کنیم
      
      // استفاده از مختصات فیزیکی به عنوان zoneLabel
      final zoneLabel = 'MapRef_${_selectedPoint!.index}_X${_selectedPoint!.x.toStringAsFixed(2)}_Y${_selectedPoint!.y.toStringAsFixed(2)}';
      
      // برای latitude و longitude، از مقادیر پیش‌فرض استفاده می‌کنیم
      // یا می‌توانیم از موقعیت GPS فعلی استفاده کنیم (اگر در دسترس باشد)
      // در اینجا از مقادیر ثابت استفاده می‌کنیم و zoneLabel را برای شناسایی استفاده می‌کنیم
      const baseLat = 0.0; // می‌تواند از GPS گرفته شود
      const baseLon = 0.0; // می‌تواند از GPS گرفته شود
      
      await widget.fingerprintService.saveFingerprint(
        latitude: baseLat + _selectedPoint!.x / 111320.0, // تقریباً 1 درجه = 111320 متر
        longitude: baseLon + _selectedPoint!.y / (111320.0 * math.cos(baseLat * math.pi / 180)),
        zoneLabel: zoneLabel,
        scanResult: scanResult,
      );
      
      // ذخیره در CSV خودکار
      await AutoCsvService.addScan(
        scanResult: scanResult,
        latitude: baseLat + _selectedPoint!.x / 111320.0,
        longitude: baseLon + _selectedPoint!.y / (111320.0 * math.cos(baseLat * math.pi / 180)),
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
            content: Text('RSSI برای نقطه ${_selectedPoint!.index} ثبت شد!'),
            backgroundColor: Colors.green,
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
                // دکمه انتخاب تصویر
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _pickMapImage,
                    icon: const Icon(Icons.image),
                    label: const Text('انتخاب تصویر نقشه'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // تنظیم ضریب مقیاس
                Row(
                  children: [
                    const Text('ضریب مقیاس (پیکسل/متر):'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _scaleController,
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
              ],
            ),
          ),
          // نمایش نقشه و نقاط
          Expanded(
            child: _mapImageFile == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'لطفاً یک تصویر نقشه انتخاب کنید',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : _buildMapWithPoints(),
          ),
        ],
      ),
    );
  }

  /// ساخت ویجت نقشه با نقاط
  Widget _buildMapWithPoints() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            final imageDisplaySize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            _handleImageTap(details, imageDisplaySize);
          },
          child: Stack(
            children: [
              // تصویر نقشه
              Center(
                child: _mapImageProvider != null
                    ? Image(
                        key: _imageKey,
                        image: _mapImageProvider!,
                        fit: BoxFit.contain,
                      )
                    : const CircularProgressIndicator(),
              ),
              // نمایش نقاط مرجع
              if (_imageSize != null && _originPoint != null)
                ..._referencePoints.map((point) {
                  // محاسبه موقعیت نقطه روی صفحه نمایش
                  // باید با همان منطق scale که در _handleImageTap استفاده می‌شود هماهنگ باشد
                  final imageAspectRatio = _imageSize!.width / _imageSize!.height;
                  final displayAspectRatio = constraints.maxWidth / constraints.maxHeight;
                  
                  double scaleX, scaleY;
                  double offsetX = 0, offsetY = 0;
                  
                  if (imageAspectRatio > displayAspectRatio) {
                    scaleX = scaleY = _imageSize!.width / constraints.maxWidth;
                    offsetY = (constraints.maxHeight - _imageSize!.height / scaleX) / 2;
                  } else {
                    scaleX = scaleY = _imageSize!.height / constraints.maxHeight;
                    offsetX = (constraints.maxWidth - _imageSize!.width / scaleY) / 2;
                  }
                  
                  final displayX = point.pixelPosition.dx / scaleX + offsetX;
                  final displayY = point.pixelPosition.dy / scaleY + offsetY;
                  
                  return Positioned(
                    left: displayX - 8,
                    top: displayY - 8,
                    child: GestureDetector(
                      onTap: () => _selectPoint(point),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: point.index == 0
                              ? Colors.red
                              : point.isRecorded
                                  ? Colors.green
                                  : point == _selectedPoint
                                      ? Colors.blue
                                      : Colors.orange,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        child: point.index == 0
                            ? const Icon(
                                Icons.center_focus_strong,
                                size: 10,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
            ],
          ),
        );
      },
    );
  }
}

