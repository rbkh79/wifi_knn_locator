import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../wifi_scanner.dart';
import '../cell_scanner.dart';
import '../services/unified_localization_service.dart';
import '../services/settings_service.dart';
import '../services/auto_csv_service.dart';
import '../services/location_service.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../models/environment_type.dart';
import '../widgets/operator_status_header.dart';
import '../widgets/position_map_widget.dart';
import '../widgets/coordinate_panel.dart';
import 'settings_screen.dart';
import 'location_history_screen.dart';
import 'location_history_screen.dart';

/// صفحه اصلی واحد برای موقعیت‌یابی
class SinglePageLocalizationScreen extends StatefulWidget {
  const SinglePageLocalizationScreen({Key? key}) : super(key: key);

  @override
  State<SinglePageLocalizationScreen> createState() =>
      _SinglePageLocalizationScreenState();
}

enum ScanState { idle, scanning, success, error }

class _SinglePageLocalizationScreenState
    extends State<SinglePageLocalizationScreen> with WidgetsBindingObserver {
  // حالت اسکن
  ScanState _scanState = ScanState.idle;
  bool _isScanning = false;

  // حالت پژوهشی
  bool _researchMode = false;

  // متریک‌های اسکن و K
  int? _scanLatencyMs;
  int? _activeSignalCount;
  int? _kUsed;
  int _currentK = AppConfig.defaultK;

  // داده‌های موقعیت
  LocationEstimate? _currentPosition;
  EnvironmentType _environmentType = EnvironmentType.unknown;
  List<LocationEstimate> _trajectoryHistory = [];

  // داده‌های اسکن برای ذخیره در حالت پژوهشگر
  WifiScanResult? _lastWifiScan;
  CellScanResult? _lastCellScan;
  Position? _lastGpsPosition;

  // اطلاعات اپراتور
  String _operatorName = 'نامشناخته';
  String _networkType = 'نامشناخته';
  int _signalStrength = 0;

  // اطلاعات دستگاه
  double _batteryLevel = 0.8;
  bool _isCharging = false;

  // سرویس‌ها
  late UnifiedLocalizationService _localizationService;
  late LocalDatabase _database;

  // Global key برای nقشه (dynamic)
  final GlobalKey<dynamic> _mapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _database = LocalDatabase.instance;
    _localizationService = UnifiedLocalizationService(_database);
    
    // بارگذاری حالت پژوهشی
    SettingsService.getBool('research_mode').then((v) {
      setState(() {
        _researchMode = v ?? false;
      });
    });

    // آپدیت اطلاعات اپراتور و باتری
    _updateOperatorInfo();
    _updateBatteryInfo();

    // مقداردهی اولیه سرویس CSV خودکار
    AutoCsvService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _centerMap() {
    // instruct child widget to re-center on currentPosition
    _mapKey.currentState?.centerOnCurrent();
  }

  Future<void> _openHistory() async {
    final entry = await Navigator.of(context).push<LocationHistoryEntry>(
      MaterialPageRoute(builder: (_) => const LocationHistoryScreen()),
    );
    if (entry != null) {
      // convert history entry to LocationEstimate-like display
      setState(() {
        _currentPosition = LocationEstimate(
          latitude: entry.latitude,
          longitude: entry.longitude,
          confidence: entry.confidence,
          zoneLabel: entry.zoneLabel,
          nearestNeighbors: const [],
          averageDistance: 0.0,
        );
        _environmentType = _environmentTypeLabelToType(entry.zoneLabel ?? '');
        _trajectoryHistory.add(_currentPosition!);
      });
      _centerMap();
    }
  }

  EnvironmentType _environmentTypeLabelToType(String label) {
    switch (label) {
      case 'داخلی':
        return EnvironmentType.indoor;
      case 'خارجی':
        return EnvironmentType.outdoor;
      case 'ترکیبی':
        return EnvironmentType.hybrid;
      default:
        return EnvironmentType.unknown;
    }
  }

  void _updateOperatorInfo() {
    // در عملی، این اطلاعات از سرویس‌های دستگاه می‌آیند
    setState(() {
      _operatorName = 'همراه اول';
      _networkType = '4G';
      _signalStrength = 75;
    });
  }

  void _updateBatteryInfo() {
    // در عملی، این اطلاعات از Battery Plugin می‌آیند
    setState(() {
      _batteryLevel = 0.8;
      _isCharging = false;
    });
  }

  Future<void> _performScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanState = ScanState.scanning;
      // داده‌های قبلی را نگه می‌داریم تا در صورت خطا از دست نروند
      // بعد از موفقیت اسکن، داده‌های جدید جایگزین می‌شوند
    });

    final sw = Stopwatch()..start();
    try {
      // اسکن Wi-Fi، BTS و GPS را موازی اجرا می‌کنیم (سریع‌تر)
      debugPrint('=== شروع اسکن موازی ===');
      final results = await Future.wait([
        WifiScanner.performScan(),
        CellScanner.performScan(),
        LocationService.getCurrentPosition(),
      ]);

      final wifiResult = results[0] as WifiScanResult;
      final cellResult = results[1] as CellScanResult;
      final gpsPosition = results[2] as Position?;

      debugPrint('✓ WiFi: ${wifiResult.accessPoints.length} APs');
      debugPrint('✓ BTS: ${cellResult.allCells.length} cells');
      debugPrint('✓ GPS: ${gpsPosition != null ? "${gpsPosition.latitude}, ${gpsPosition.longitude}" : "null"}');

      // ذخیره برای استفاده در _savePosition
      setState(() {
        _lastWifiScan = wifiResult;
        _lastCellScan = cellResult;
        _lastGpsPosition = gpsPosition;
      });

      if (cellResult.allCells.isEmpty) {
        debugPrint('⚠ BTS خالی است - ممکن است مجوز READ_PHONE_STATE نداشته باشید');
      }
      if (gpsPosition == null) {
        debugPrint('⚠ GPS null است - ممکن است سرویس موقعیت غیرفعال باشد');
      }

      // موقعیت‌یابی یکپارچه
      UnifiedLocalizationResult? localizationResult;
      try {
        localizationResult = await _localizationService.performLocalization(
          deviceId: 'user-device',
          k: _currentK,
        );
      } catch (e) {
        debugPrint('⚠ خطا در موقعیت‌یابی: $e - ادامه با ذخیره CSV...');
      }

      sw.stop();
      _scanLatencyMs = sw.elapsedMilliseconds;
      _activeSignalCount = wifiResult.accessPoints.length + cellResult.allCells.length;
      if (localizationResult != null) {
        _kUsed = localizationResult.kUsed;
        _currentK = localizationResult.kUsed;
      }

      // همیشه CSV را ذخیره کن - حتی اگر موقعیت‌یابی شکست خورد
      await AutoCsvService.saveScanToCsv(
        scanResult: wifiResult,
        cellScanResult: cellResult,
        gpsPosition: gpsPosition,
        knnEstimate: localizationResult?.estimate,
        isReliable: localizationResult?.isReliable,
        isNewLocation: null,
        gpsKnnDistance: null,
      );

      setState(() {
        if (localizationResult != null && localizationResult.estimate != null && localizationResult.isReliable) {
          _currentPosition = localizationResult.estimate;
          _environmentType = _mapEnvironmentTypeFromEnum(localizationResult.environmentType);
          _trajectoryHistory.add(localizationResult.estimate!);
          _scanState = ScanState.success;
        } else if (wifiResult.accessPoints.isNotEmpty || cellResult.allCells.isNotEmpty || gpsPosition != null) {
          // حتی اگر KNN شکست خورد، داده‌های خام را داریم
          _scanState = ScanState.success;
        } else {
          _scanState = ScanState.error;
        }
      });
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      setState(() => _scanState = ScanState.error);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در اسکن: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isScanning = false);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _scanState = ScanState.idle);
      }
    }
  }

  Future<void> _savePosition() async {
    debugPrint('=== _savePosition شروع ===');
    debugPrint('_currentPosition: $_currentPosition');
    debugPrint('_lastWifiScan: ${_lastWifiScan != null ? "exists (${_lastWifiScan!.accessPoints.length} APs)" : "null"}');
    debugPrint('_lastCellScan: ${_lastCellScan != null ? "exists (${_lastCellScan!.allCells.length} cells)" : "null"}');
    debugPrint('_lastGpsPosition: ${_lastGpsPosition != null ? "${_lastGpsPosition!.latitude}, ${_lastGpsPosition!.longitude}" : "null"}');

    // اگر BTS یا GPS موجود نیست، حتماً دریافت کن (برای ذخیره در CSV)
    if (_lastCellScan == null || _lastGpsPosition == null) {
      debugPrint('BTS یا GPS موجود نیست - دریافت داده‌های تازه...');
      setState(() => _isScanning = true);
      try {
        final results = await Future.wait([
          LocationService.getCurrentPosition(),
          CellScanner.performScan(),
        ]);
        final gpsPos = results[0] as Position?;
        final cellResult = results[1] as CellScanResult;
        
        setState(() {
          if (gpsPos != null) _lastGpsPosition = gpsPos;
          if (cellResult.allCells.isNotEmpty) _lastCellScan = cellResult;
        });
        debugPrint('✓ GPS تازه: ${gpsPos != null ? "${gpsPos.latitude}, ${gpsPos.longitude}" : "null"}');
        debugPrint('✓ BTS تازه: ${cellResult.allCells.length} cells');
      } catch (e) {
        debugPrint('❌ خطا در دریافت داده: $e');
      } finally {
        setState(() => _isScanning = false);
      }
    }

    int savedCount = 0;
    final errors = <String>[];

    try {
      // ۱. ذخیره موقعیت KNN در location_history (اگر موجود باشد)
      if (_currentPosition != null) {
        try {
          await _database.insertLocationHistory(
            LocationHistoryEntry(
              deviceId: 'user-device',
              latitude: _currentPosition!.latitude,
              longitude: _currentPosition!.longitude,
              zoneLabel: _environmentTypeLabel(),
              confidence: _currentPosition!.confidence,
              timestamp: DateTime.now(),
            ),
          );
          savedCount++;
          debugPrint('✓ KNN location saved');
        } catch (e) {
          errors.add('KNN: $e');
          debugPrint('❌ KNN save error: $e');
        }
      }

      // ۲. ذخیره BTS
      final cellsToSave = _lastCellScan?.allCells ?? [];
      if (cellsToSave.isNotEmpty) {
        try {
          final fingerprintId = 'cell_${DateTime.now().millisecondsSinceEpoch}';
          final refLat = _currentPosition?.latitude ?? _lastGpsPosition?.latitude ?? 0.0;
          final refLon = _currentPosition?.longitude ?? _lastGpsPosition?.longitude ?? 0.0;
          await _database.insertCellFingerprint(
            CellFingerprintEntry(
              fingerprintId: fingerprintId,
              latitude: refLat,
              longitude: refLon,
              zoneLabel: _environmentTypeLabel(),
              cellTowers: cellsToSave,
              createdAt: DateTime.now(),
              deviceId: 'user-device',
            ),
          );
          savedCount++;
          debugPrint('✓ BTS saved: ${cellsToSave.length} cells');
        } catch (e) {
          errors.add('BTS: $e');
          debugPrint('❌ BTS save error: $e');
        }
      } else {
        debugPrint('⚠ BTS: هیچ سلولی برای ذخیره وجود ندارد');
        // تلاش مجدد برای دریافت BTS
        try {
          debugPrint('تلاش مجدد برای اسکن BTS...');
          final freshCell = await CellScanner.performScan();
          if (freshCell.allCells.isNotEmpty) {
            setState(() => _lastCellScan = freshCell);
            final fingerprintId = 'cell_${DateTime.now().millisecondsSinceEpoch}';
            final refLat = _currentPosition?.latitude ?? _lastGpsPosition?.latitude ?? 0.0;
            final refLon = _currentPosition?.longitude ?? _lastGpsPosition?.longitude ?? 0.0;
            await _database.insertCellFingerprint(
              CellFingerprintEntry(
                fingerprintId: fingerprintId,
                latitude: refLat,
                longitude: refLon,
                zoneLabel: _environmentTypeLabel(),
                cellTowers: freshCell.allCells,
                createdAt: DateTime.now(),
                deviceId: 'user-device',
              ),
            );
            savedCount++;
            debugPrint('✓ Fresh BTS saved: ${freshCell.allCells.length} cells');
          } else {
            debugPrint('⚠ Fresh BTS هم خالی است - مجوز READ_PHONE_STATE را بررسی کنید');
          }
        } catch (e) {
          errors.add('Fresh BTS: $e');
          debugPrint('❌ Fresh BTS error: $e');
        }
      }

      // ۳. ذخیره GPS
      Position? gpsToSave = _lastGpsPosition;
      if (gpsToSave == null) {
        // تلاش مجدد برای دریافت GPS
        debugPrint('GPS null - تلاش مجدد...');
        try {
          gpsToSave = await LocationService.getCurrentPosition();
          if (gpsToSave != null) {
            setState(() => _lastGpsPosition = gpsToSave);
          }
        } catch (e) {
          debugPrint('❌ Fresh GPS error: $e');
        }
      }

      if (gpsToSave != null) {
        try {
          await _database.insertLocationHistory(
            LocationHistoryEntry(
              deviceId: 'user-device',
              latitude: gpsToSave.latitude,
              longitude: gpsToSave.longitude,
              zoneLabel: 'GPS',
              confidence: 1.0,
              timestamp: DateTime.now(),
            ),
          );
          savedCount++;
          debugPrint('✓ GPS saved: ${gpsToSave.latitude}, ${gpsToSave.longitude}');
        } catch (e) {
          errors.add('GPS: $e');
          debugPrint('❌ GPS save error: $e');
        }
      } else {
        debugPrint('⚠ GPS: موقعیت در دسترس نیست');
      }

      // ۴. ذخیره در CSV - همیشه اجرا شود حتی بدون WiFi
      try {
        // اگر WiFi scan نداریم، یک WifiScanResult خالی بسازیم
        final wifiScan = _lastWifiScan ?? WifiScanResult(
          deviceId: 'user-device',
          timestamp: DateTime.now(),
          accessPoints: [],
        );
        await AutoCsvService.saveScanToCsv(
          scanResult: wifiScan,
          cellScanResult: _lastCellScan,
          gpsPosition: gpsToSave ?? _lastGpsPosition,
          knnEstimate: _currentPosition,
          isReliable: _currentPosition != null ? _currentPosition!.confidence >= AppConfig.confidenceThreshold : null,
          isNewLocation: null,
          gpsKnnDistance: null,
        );
        savedCount++;
        debugPrint('✓ CSV saved: WiFi=${wifiScan.accessPoints.length} APs, BTS=${_lastCellScan?.allCells.length ?? 0} cells, GPS=${gpsToSave != null || _lastGpsPosition != null ? "yes" : "no"}');
      } catch (e) {
        errors.add('CSV: $e');
        debugPrint('❌ CSV save error: $e');
      }

      // نمایش نتیجه
      if (mounted) {
        if (errors.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ $savedCount مورد با موفقیت ذخیره شد'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          final msg = savedCount > 0
              ? '⚠ $savedCount مورد ذخیره شد، خطا: ${errors.join(", ")}'
              : '❌ خطا در ذخیره: ${errors.join(", ")}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: savedCount > 0 ? Colors.orange : Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطای غیرمنتظره در _savePosition: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _environmentTypeLabel() {
    switch (_environmentType) {
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

  EnvironmentType _mapEnvironmentTypeFromEnum(String envType) {
    switch (envType) {
      case 'indoor':
        return EnvironmentType.indoor;
      case 'outdoor':
        return EnvironmentType.outdoor;
      case 'hybrid':
        return EnvironmentType.hybrid;
      default:
        return EnvironmentType.unknown;
    }
  }

  EnvironmentType _mapEnvironmentTypeFromLabel(String label) {
    switch (label) {
      case 'داخلی':
        return EnvironmentType.indoor;
      case 'خارجی':
        return EnvironmentType.outdoor;
      case 'ترکیبی':
        return EnvironmentType.hybrid;
      default:
        return EnvironmentType.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('موقعیت‌یابی هوشمند'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_researchMode ? Icons.science : Icons.science_outlined),
            tooltip: 'Research Mode',
            onPressed: () {
              setState(() {
                _researchMode = !_researchMode;
              });
              SettingsService.setBool('research_mode', _researchMode);
            },
            color: _researchMode ? Colors.amber : null,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PositionMapWidget(
                key: _mapKey,
                currentPosition: _currentPosition,
                environmentType: _environmentType,
                trajectoryHistory: _trajectoryHistory,
                isScanning: _isScanning,
                onCenterPressed: _centerMap,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withOpacity(0.9),
                      Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: OperatorStatusHeader(
                  operatorName: _operatorName,
                  networkType: _networkType,
                  signalStrength: _signalStrength,
                  environmentType: _environmentType,
                  batteryLevel: _batteryLevel,
                  isCharging: _isCharging,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CoordinatePanel(
                estimate: _currentPosition,
                environmentType: _environmentType,
                operatorName: _operatorName,
                isLoading: _isScanning,
                onScan: _performScan,
                onSave: _savePosition,
                researchMode: _researchMode,
                scanLatencyMs: _scanLatencyMs,
                signalCount: _activeSignalCount,
                kUsed: _kUsed ?? _currentK,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildScanButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildScanButton() {
    Color bgColor;
    IconData icon;

    switch (_scanState) {
      case ScanState.scanning:
        bgColor = Colors.orange;
        icon = Icons.hourglass_empty;
        break;
      case ScanState.success:
        bgColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case ScanState.error:
        bgColor = Colors.red;
        icon = Icons.error;
        break;
      case ScanState.idle:
      default:
        bgColor = Theme.of(context).colorScheme.secondary;
        icon = Icons.my_location;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: _isScanning ? null : _performScan,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: _isScanning
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(icon, color: Colors.white),
      ),
    );
  }

}
