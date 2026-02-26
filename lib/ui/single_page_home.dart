import 'package:flutter/material.dart';
import '../config.dart';
import '../wifi_scanner.dart';
import '../cell_scanner.dart';
import '../services/unified_localization_service.dart';
import '../services/settings_service.dart';
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
            content: const Text('خطا در اسکن. لطفاً دوباره تلاش کنید.'),
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
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هنوز موقعیتی برای ذخیره وجود ندارد.'),
        ),
      );
      return;
    }

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ موقعیت با موفقیت ذخیره شد'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
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
      appBar: AppBar(
        title: const Text('موقعیت‌یابی هوشمند'),
        elevation: 0,
        actions: [
          // Research mode toggle
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
            onPressed: () async {
              final selected = await Navigator.of(context).push<LocationHistoryEntry>(
                MaterialPageRoute(builder: (_) => const LocationHistoryScreen()),
              );
              if (selected != null) {
                setState(() {
                  _currentPosition = LocationEstimate(
                    latitude: selected.latitude,
                    longitude: selected.longitude,
                    confidence: selected.confidence ?? 0.5,
                    nearestNeighbors: [],
                  );
                  _environmentType = _mapEnvironmentTypeFromLabel(selected.zoneLabel ?? '');
                });
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // بخش هدر (اپراتور و سیگنال)
            OperatorStatusHeader(
              operatorName: _operatorName,
              networkType: _networkType,
              signalStrength: _signalStrength,
              environmentType: _environmentType,
              batteryLevel: _batteryLevel,
              isCharging: _isCharging,
            ),

            // بخش نقشه
            Expanded(
              flex: 7,
              child: PositionMapWidget(
                key: _mapKey,
                currentPosition: _currentPosition,
                environmentType: _environmentType,
                trajectoryHistory: _trajectoryHistory,
                isScanning: _isScanning,
                onCenterPressed: () {
                  try {
                    final state = _mapKey.currentState as dynamic;
                    state?.centerOnCurrent();
                  } catch (e) {
                    debugPrint('Error centering map: $e');
                  }
                },
              ),
            ),

            // بخش پنل مختصات (Draggable)
            Expanded(
              flex: 3,
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

      // دکمه اسکن ثابت (FAB)
      floatingActionButton: _buildScanButton(),
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
        bgColor = Theme.of(context).primaryColor;
        icon = Icons.my_location;
    }

    return FloatingActionButton(
      onPressed: _isScanning ? null : _performScan,
      backgroundColor: bgColor,
      child: _isScanning
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Icon(icon),
    );
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
}
