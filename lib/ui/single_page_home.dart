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
    });

    final sw = Stopwatch()..start();
    try {
      // اسکن Wi-Fi
      final wifiResult = await WifiScanner.performScan();
      debugPrint('WiFi Scan: ${wifiResult.accessPoints.length} APs found');

      // اسکن سلولی
      final cellResult = await CellScanner.performScan();
      debugPrint('Cell Scan: ${cellResult.allCells.length} cells found');

      final gpsPosition = await LocationService.getCurrentPosition();
      debugPrint('GPS Position: ${gpsPosition?.latitude}, ${gpsPosition?.longitude}');

      // ذخیره برای استفاده در حالت پژوهشگر
      setState(() {
        _lastWifiScan = wifiResult;
        _lastCellScan = cellResult;
        _lastGpsPosition = gpsPosition;
      });
      debugPrint('Saved scan data: WiFi=${wifiResult.accessPoints.length}, BTS=${cellResult.allCells.length}, GPS=${gpsPosition != null}');

      // اگر BTS خالی است، هشدار بده
      if (cellResult.allCells.isEmpty) {
        debugPrint('⚠ WARNING: No BTS cells found. BTS data will not be saved.');
      }

      // موقعیت‌یابی یکپارچه
      final result = await _localizationService.performLocalization(
        deviceId: 'user-device',
        k: _currentK,
      );

      sw.stop();
      _scanLatencyMs = sw.elapsedMilliseconds;
      _activeSignalCount = wifiResult.accessPoints.length + cellResult.allCells.length;
      _kUsed = result.kUsed;
      _currentK = result.kUsed;

      await AutoCsvService.saveScanToCsv(
        scanResult: wifiResult,
        cellScanResult: cellResult,
        gpsPosition: gpsPosition,
        knnEstimate: result.estimate,
        isReliable: result.isReliable,
        isNewLocation: null,
        gpsKnnDistance: null,
      );

      setState(() {
        if (result.estimate != null && result.isReliable) {
          _currentPosition = result.estimate;
          _environmentType = _mapEnvironmentTypeFromEnum(result.environmentType);
          _trajectoryHistory.add(result.estimate!);
          _scanState = ScanState.success;
        } else {
          _scanState = ScanState.error;
        }
      });
    } catch (e) {
      debugPrint('Scan error: $e');
      setState(() => _scanState = ScanState.error);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('خطا در اسکن BTS و WiFi. لطفاً دوباره تلاش کنید.'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isScanning = false);
      
      // بازگشت به حالت خواموش بعد از 2 ثانیه
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _scanState = ScanState.idle);
      }
    }
  }

  Future<void> _savePosition() async {
    debugPrint('=== _savePosition شروع ===');
    debugPrint('_currentPosition: $_currentPosition');
    debugPrint('_lastCellScan: ${_lastCellScan != null ? "exists" : "null"}');
    debugPrint('_lastGpsPosition: ${_lastGpsPosition != null ? "exists" : "null"}');

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هنوز موقعیتی برای ذخیره وجود ندارد.'),
        ),
      );
      return;
    }

    try {
      // ذخیره موقعیت در location_history
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
      debugPrint('✓ Location history saved');

      // ذخیره BTS در cell_fingerprints (اگر BTS اسکن شده باشد)
      debugPrint('Checking BTS: _lastCellScan=${_lastCellScan != null}, allCells=${_lastCellScan?.allCells.length ?? 0}');
      if (_lastCellScan != null && _lastCellScan!.allCells.isNotEmpty) {
        final fingerprintId = 'cell_${DateTime.now().millisecondsSinceEpoch}';
        await _database.insertCellFingerprint(
          CellFingerprintEntry(
            fingerprintId: fingerprintId,
            latitude: _currentPosition!.latitude,
            longitude: _currentPosition!.longitude,
            zoneLabel: _environmentTypeLabel(),
            cellTowers: _lastCellScan!.allCells,
            createdAt: DateTime.now(),
            deviceId: 'user-device',
          ),
        );
        debugPrint('✓ BTS fingerprint saved: ${_lastCellScan!.allCells.length} cells');
      } else {
        debugPrint('⚠ BTS not saved: _lastCellScan is null or empty, trying to get fresh BTS...');
        // تلاش برای دریافت BTS مستقیم
        try {
          final freshBts = await CellScanner.performScan();
          if (freshBts.allCells.isNotEmpty) {
            final fingerprintId = 'cell_${DateTime.now().millisecondsSinceEpoch}';
            await _database.insertCellFingerprint(
              CellFingerprintEntry(
                fingerprintId: fingerprintId,
                latitude: _currentPosition!.latitude,
                longitude: _currentPosition!.longitude,
                zoneLabel: _environmentTypeLabel(),
                cellTowers: freshBts.allCells,
                createdAt: DateTime.now(),
                deviceId: 'user-device',
              ),
            );
            debugPrint('✓ Fresh BTS fingerprint saved: ${freshBts.allCells.length} cells');
          } else {
            debugPrint('⚠ Fresh BTS is also empty');
          }
        } catch (e) {
          debugPrint('❌ Error getting fresh BTS: $e');
        }
      }

      // ذخیره GPS در location_history (اگر GPS موجود باشد)
      debugPrint('Checking GPS: _lastGpsPosition=${_lastGpsPosition != null}');
      if (_lastGpsPosition != null) {
        await _database.insertLocationHistory(
          LocationHistoryEntry(
            deviceId: 'user-device',
            latitude: _lastGpsPosition!.latitude,
            longitude: _lastGpsPosition!.longitude,
            zoneLabel: 'GPS',
            confidence: 1.0,
            timestamp: DateTime.now(),
          ),
        );
        debugPrint('✓ GPS position saved: ${_lastGpsPosition!.latitude}, ${_lastGpsPosition!.longitude}');
      } else {
        debugPrint('⚠ GPS not saved: _lastGpsPosition is null, trying to get fresh GPS...');
        // تلاش برای دریافت GPS مستقیم
        try {
          final freshGps = await LocationService.getCurrentPosition();
          if (freshGps != null) {
            await _database.insertLocationHistory(
              LocationHistoryEntry(
                deviceId: 'user-device',
                latitude: freshGps.latitude,
                longitude: freshGps.longitude,
                zoneLabel: 'GPS',
                confidence: 1.0,
                timestamp: DateTime.now(),
              ),
            );
            debugPrint('✓ Fresh GPS position saved: ${freshGps.latitude}, ${freshGps.longitude}');
          } else {
            debugPrint('⚠ Fresh GPS is also null');
          }
        } catch (e) {
          debugPrint('❌ Error getting fresh GPS: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ موقعیت، BTS و GPS با موفقیت ذخیره شدند'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error in _savePosition: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره: $e'),
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
