import 'package:flutter/material.dart';
import '../config.dart';
import '../wifi_scanner.dart';
import '../cell_scanner.dart';
import '../services/unified_localization_service.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../models/environment_type.dart';
import '../widgets/operator_status_header.dart';
import '../widgets/position_map_widget.dart';
import '../widgets/coordinate_panel.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _database = LocalDatabase.instance;
    _localizationService = UnifiedLocalizationService(_database);
    
    // آپدیت اطلاعات اپراتور و باتری
    _updateOperatorInfo();
    _updateBatteryInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
      );

      setState(() {
        if (result.estimate != null && result.isReliable) {
          _currentPosition = result.estimate;
          _environmentType = _mapEnvironmentType(result.environmentType);
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

  EnvironmentType _mapEnvironmentType(String envType) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('موقعیت‌یابی هوشمند'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Navigate to settings
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // TODO: Show history
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
                currentPosition: _currentPosition,
                environmentType: _environmentType,
                trajectoryHistory: _trajectoryHistory,
                isScanning: _isScanning,
                onCenterPressed: () {
                  // TODO: Center map
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
}
