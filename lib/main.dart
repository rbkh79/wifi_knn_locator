/*
Prompt for GitHub Copilot: Update Flutter App for Indoor Wi-Fi Localization with KNN

Current App Details from README_FA.md:
- Flutter mobile app for indoor localization using Wi-Fi scans (RSSI + MAC) and KNN algorithm.
- Features: Periodic AP scanning (BSSID, RSSI, frequency, SSID); SHA-256 MAC hashing for privacy; Offline SQLite DB for fingerprints; KNN for position estimation with confidence score; Training mode for data collection; User-friendly UI with privacy info; Unit tests.
- Modular structure: lib/config.dart (K=3, scanInterval=5s), data_model.dart (WifiReading, FingerprintEntry, LocationEstimate), wifi_scanner.dart, local_database.dart, knn_localization.dart, main.dart, services/fingerprint_service.dart, utils/privacy_utils.dart.
- KNN Pseudocode: Load fingerprints, calculate Euclidean distance (default -100 dBm for missing BSSID), sort distances, select K nearest, weighted average for lat/lon, confidence = 1 / (1 + avgDistance / 100).
- DB Structure: fingerprints table (id, fingerprint_id, latitude, longitude, zone_label, created_at, device_id); access_points table (id, fingerprint_id, bssid, rssi, frequency, ssid).
- Permissions: Android ACCESS_FINE_LOCATION, etc.; iOS NSLocationWhenInUseUsageDescription.

Goal: Enhance the app to predict future position and user path based on historical Wi-Fi data (MAC/RSSI), even during Wi-Fi outages (signal cuts). Use historical data from SQLite to extrapolate paths. Add innovative features not commonly used in similar apps (up to 2025 literature).

Improvement Ideas to Implement:
1. Integrate Temporal Graph Attention Networks (TGAT) for modeling MAC relations as a temporal graph and predicting paths. Use PyTorch via flutter_torch plugin. Build graph from historical RSSI changes; predict next node (position) in knn_localization.dart.
2. Add Uncertainty-Aware Prediction with Bayesian Neural Networks (BNN) to compute prediction uncertainty. In UI, show confidence bar; during outages, warn if uncertainty high.
3. Implement Federated Learning for local model training (e.g., small LSTM) on user data without sharing raw data. Use Firebase backend to aggregate models; keep data local in SQLite.
4. Add Graph-Based Extrapolation with Temporal Graph Neural Networks (TGNN) for path prediction during outages. Detect outage (RSSI=0 threshold), extrapolate from last historical path.
5. Uncertainty-Guided Prediction with Variational Autoencoders (VAE) for handling outages: Train VAE on historical RSSI to generate probable paths; display in map UI.
6. Offline Trajectory Forecasting with Offline Reinforcement Learning (Offline RL, e.g., CQL). Model paths as action-reward sequences; predict long-term paths offline during outages.

Tasks for Copilot:
- Generate Dart code to add these features. Start with new files/modules if needed (e.g., prediction_service.dart for ML models).
- Integrate with existing: Update wifi_scanner.dart for outage detection; local_database.dart for historical data queries; knn_localization.dart for hybrid KNN + new models.
- Use torch for ML (assume flutter_torch installed); add pubspec.yaml dependencies if needed.
- Update UI in main.dart: Add path prediction display on map, outage mode switch.
- Update README_FA.md with new features, architecture, and pseudocode.
- Ensure privacy: Hash all data; no central sharing except federated gradients.
- Make it novel: These combos (e.g., TGNN for Wi-Fi outage prediction) are unpublished in 2025 literature.

Generate the updated code starting from here:
*/

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'data_model.dart';
import 'wifi_scanner.dart';
import 'cell_scanner.dart';
import 'local_database.dart';
import 'knn_localization.dart';
import 'services/fingerprint_service.dart';
import 'services/location_service.dart';
import 'services/settings_service.dart';
import 'services/data_logger_service.dart';
import 'services/movement_prediction_service.dart';
import 'services/data_export_service.dart';
import 'services/fingerprint_validator.dart';
import 'services/path_analysis_service.dart';
import 'services/location_confidence_service.dart';
import 'services/auto_csv_service.dart';
import 'services/map_reference_point_picker.dart';
import 'services/unified_localization_service.dart';
import 'services/trajectory_service.dart';
import 'services/path_prediction_service.dart';
import 'services/motion_detection_service.dart';
import 'widgets/environment_indicator.dart';
import 'widgets/trajectory_display.dart';
import 'widgets/prediction_display.dart';
import 'utils/privacy_utils.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi KNN Locator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // State variables
  bool _loading = false;
  bool _isTrainingMode = false;
  WifiScanResult? _currentScanResult;
  LocationEstimate? _locationEstimate;
  MovementPrediction? _movementPrediction;
  Position? _currentPosition;
  String? _deviceId;
  int _fingerprintCount = 0;
  bool _useGeolocation = true;
  bool _loadingLocation = false;
  List<FingerprintEntry> _fingerprintEntries = [];
  
  // Expansion states
  bool _expandedDeviceLocation = false;
  bool _expandedWifiScan = false;
  bool _expandedSignalResults = false;
  bool _expandedSettings = false;
  bool _expandedMap = true;
  bool _expandedResearcherMode = false;
  bool _useValidation = true; // استفاده از validation برای fingerprintها
  
  // Services
  late final LocalDatabase _database;
  late final KnnLocalization _knnLocalization;
  late final FingerprintService _fingerprintService;
  late final DataLoggerService _dataLogger;
  late final MovementPredictionService _movementPredictionService;
  late final DataExportService _dataExportService;
  late final PathAnalysisService _pathAnalysisService;
  late final LocationConfidenceService _locationConfidenceService;
  late final UnifiedLocalizationService _unifiedLocalizationService;
  
  // Unified localization state
  UnifiedLocalizationResult? _unifiedResult;
  PathPredictionResult? _pathPrediction;
  List<TrajectoryPoint> _trajectory = [];
  
  // Path visualization
  List<LocationHistoryEntry> _userPath = [];
  bool _showPath = true;
  
  // Location confidence state
  ConfidenceResult? _confidenceResult;

  // Motion-aware scanning
  late final MotionDetectionService _motionService;
  StreamSubscription<MotionState>? _motionSub;
  Timer? _autoScanTimer;
  MotionState _motionState = MotionState.unknown;

  // آخرین اسکن سلولی برای نمایش اپراتور
  CellScanResult? _lastCellScan;
  
  // UI Controllers
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();
  final TextEditingController _zoneController = TextEditingController();
  final MapController _mapController = MapController();
  final TextEditingController _contextController = TextEditingController();

  // Session & context state
  final Uuid _uuid = const Uuid();
  String? _currentSessionId;
  String? _selectedTrajectorySessionId;
  List<TrainingSession> _recentSessions = [];
  List<FingerprintEntry> _selectedSessionTrajectory = [];
  List<String> _availableContexts = ['Default'];
  String? _currentContext = 'Default';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _database = LocalDatabase.instance;
    _knnLocalization = KnnLocalization(_database);
    _fingerprintService = FingerprintService(_database);
    _dataLogger = DataLoggerService(_database);
    _movementPredictionService = MovementPredictionService(_database);
    _dataExportService = DataExportService(_database);
    _pathAnalysisService = PathAnalysisService(_database);
    _locationConfidenceService = LocationConfidenceService(_database);
    _unifiedLocalizationService = UnifiedLocalizationService(_database);
    _motionService = MotionDetectionService();
    
    // دریافت شناسه دستگاه
    _deviceId = await PrivacyUtils.getDeviceId();
    
    // بارگذاری تنظیمات
    _useGeolocation = await SettingsService.getUseGeolocation();
    
    // مقداردهی اولیه سرویس CSV خودکار
    await AutoCsvService.initialize();
    
    // بارگذاری تعداد اثرانگشت‌ها
    _updateFingerprintCount();
    await _loadFingerprintEntries();
    
    // شروع سرویس تشخیص حرکت
    _motionService.start();
    _motionSub =
        _motionService.motionStateStream.listen(_onMotionStateChanged);

    // بارگذاری مسیر کاربر
    await _loadUserPath();
    await _loadContextAndSessions();
    
    setState(() {});
  }

  void _onMotionStateChanged(MotionState state) {
    if (!mounted) return;
    setState(() {
      _motionState = state;
    });

    // توقف تایمر قبلی
    _autoScanTimer?.cancel();

    final interval = _motionService.recommendedScanInterval;

    // توقف ناگهانی: اسکن فوری برای ثبت موقعیت دقیق
    if (_motionService.justStopped && !_loading) {
      _performScan();
    }

    // تایمر جدید بر اساس حالت حرکت
    _autoScanTimer = Timer.periodic(interval, (_) {
      if (!_loading) {
        _performScan();
      }
    });
  }

  /// بارگذاری مسیر کاربر برای نمایش روی نقشه
  Future<void> _loadUserPath() async {
    if (_deviceId == null) return;
    
    try {
      final path = await _pathAnalysisService.getUserPath(_deviceId!);
      if (mounted) {
        setState(() {
          _userPath = path;
        });
      }
    } catch (e) {
      debugPrint('Error loading user path: $e');
    }
  }

  Future<void> _loadTrajectoryForSession(String sessionId) async {
    try {
      final entries = await _database.getFingerprintsBySession(sessionId);
      if (mounted) {
        setState(() {
          _selectedTrajectorySessionId = sessionId;
          _selectedSessionTrajectory = entries;
        });
      }
    } catch (e) {
      debugPrint('Error loading trajectory for session $sessionId: $e');
    }
  }

  Future<void> _updateFingerprintCount() async {
    _fingerprintCount = await _fingerprintService.getFingerprintCount();
    if (mounted) setState(() {});
  }

  Future<void> _loadFingerprintEntries() async {
    final entries = await _fingerprintService.getAllFingerprints();
    if (mounted) {
      setState(() {
        _fingerprintEntries = entries;
      });
      if (entries.isNotEmpty) {
        final first = entries.first;
        _mapController.move(
          LatLng(first.latitude, first.longitude),
          AppConfig.defaultMapZoom,
        );
      }
    }
  }

  Future<void> _loadContextAndSessions() async {
    final contexts = await _database.getAvailableContexts();
    final sessions = await _database.getTrainingSessions(limit: 20);
    if (mounted) {
      setState(() {
        if (contexts.isNotEmpty) {
          _availableContexts = contexts;
          _currentContext ??= contexts.first;
        }
        _recentSessions = sessions;
      });
    }

    if (_currentSessionId == null) {
      if (sessions.isNotEmpty) {
        _currentSessionId = sessions.first.sessionId;
        await _loadTrajectoryForSession(_currentSessionId!);
      } else {
        await _startNewSession();
      }
    }
  }

  Future<void> _startNewSession({String? contextId}) async {
    final newSessionId = 'session_${_uuid.v4()}';
    final session = TrainingSession(
      sessionId: newSessionId,
      contextId: contextId ?? _currentContext,
      startedAt: DateTime.now(),
    );
    await _database.upsertTrainingSession(session);
    if (mounted) {
      setState(() {
        _currentSessionId = newSessionId;
        _recentSessions = [session, ..._recentSessions];
      });
    }
    await _loadTrajectoryForSession(newSessionId);
  }

  Future<void> _finishCurrentSession() async {
    if (_currentSessionId == null) return;
    await _database.finishTrainingSession(_currentSessionId!);
    await _loadContextAndSessions();
  }

  Future<void> _setContext(String contextId) async {
    setState(() {
      _currentContext = contextId;
    });
    // به صورت خودکار جلسه جدید با زمینه جدید شروع می‌شود
    await _startNewSession(contextId: contextId);
  }

  Future<bool> _ensureTrainingSession() async {
    if (_currentSessionId == null) {
      await _startNewSession();
    }
    return _currentSessionId != null;
  }

  Future<void> _getDeviceLocation() async {
    if (!_useGeolocation) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('استفاده از موقعیت جغرافیایی غیرفعال است. لطفاً در تنظیمات فعال کنید.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
  }

    setState(() {
      _loadingLocation = true;
    });

    try {
      final position = await LocationService.getCurrentPosition();
      
      setState(() {
        _currentPosition = position;
        _loadingLocation = false;
      });

      if (position == null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
            content: Text('نمی‌توان موقعیت را دریافت کرد. لطفاً مجوزها را بررسی کنید.'),
                backgroundColor: Colors.red,
              ),
            );
          }
    } catch (e) {
        setState(() {
        _loadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دریافت موقعیت: $e'),
            backgroundColor: Colors.red,
            ),
          );
        }
    }
      }

  Future<void> _performScan() async {
    setState(() {
      _loading = true;
      _currentScanResult = null;
      _locationEstimate = null;
      _movementPrediction = null;
      _unifiedResult = null;
      _pathPrediction = null;
    });

    try {
      // اجرای اسکن Wi-Fi - حتی اگر GPS خاموش باشد
      final scanResult = await WifiScanner.performScan();
      
      // اجرای اسکن Cell (برای موقعیت‌یابی Outdoor)
      CellScanResult? cellScanResult;
      try {
        cellScanResult = await CellScanner.performScan();
      } catch (e) {
        debugPrint('Cell scan failed: $e');
        // ادامه می‌دهیم حتی اگر Cell scan شکست بخورد
      }

      // ثبت تاریخچه اسکن
      await _dataLogger.logWifiScan(scanResult);
      await _storeRawScan(scanResult);

      setState(() {
        _currentScanResult = scanResult;
        _lastCellScan = cellScanResult;
        _expandedSignalResults = true; // باز کردن بخش نتایج
      });

      // بررسی اینکه آیا سیگنالی (Wi-Fi یا Cell) پیدا شده است
      final hasWifi = scanResult.accessPoints.isNotEmpty;
      final hasCell = cellScanResult != null && 
                      (cellScanResult.servingCell != null || 
                       cellScanResult.neighboringCells.isNotEmpty);

      if (!hasWifi && !hasCell) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'هیچ سیگنالی (Wi-Fi یا Cell) یافت نشد.\n'
                'لطفاً:\n'
                '1. Wi-Fi یا داده موبایل را روشن کنید\n'
                '2. مجوز Location و Phone را در تنظیمات فعال کنید\n'
                '3. دوباره تلاش کنید',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // ذخیره خودکار در CSV (قبل از هر پردازشی)
      await AutoCsvService.saveScanToCsv(
        scanResult: scanResult,
        gpsPosition: _currentPosition,
        knnEstimate: null, // بعداً پر می‌شود
        isReliable: null,
        isNewLocation: null,
        gpsKnnDistance: null,
      );

      // اگر در حالت آموزش نیستیم، تخمین موقعیت یکپارچه انجام می‌دهیم
      if (!_isTrainingMode && _deviceId != null) {
        // استفاده از UnifiedLocalizationService برای پشتیبانی از Indoor و Outdoor
        final unifiedResult = await _unifiedLocalizationService.performLocalization(
          deviceId: _deviceId!,
          preferIndoor: true,
        );

        // بارگذاری مسیر حرکت
        _trajectory = await _unifiedLocalizationService.getRecentTrajectory(
          deviceId: _deviceId!,
          limit: 50,
        );

        // پیش‌بینی مسیر آینده
        _pathPrediction = await _unifiedLocalizationService.predictPath(
          deviceId: _deviceId!,
          method: 'markov',
          steps: 3,
        );

        final estimate = unifiedResult.estimate;

        // بررسی اطمینان موقعیت
        final confidenceResult = await _locationConfidenceService.checkLocationConfidence(
          knnEstimate: estimate,
          gpsPosition: _currentPosition,
          scanResult: scanResult,
        );

        setState(() {
          _locationEstimate = estimate;
          _confidenceResult = confidenceResult;
          _unifiedResult = unifiedResult;
        });

        // ذخیره مجدد CSV با اطلاعات کامل (KNN و confidence)
        await AutoCsvService.saveScanToCsv(
          scanResult: scanResult,
          gpsPosition: _currentPosition,
          knnEstimate: estimate,
          isReliable: confidenceResult.isReliable,
          isNewLocation: confidenceResult.isNewLocation,
          gpsKnnDistance: confidenceResult.gpsKnnDistance,
        );

        // نمایش هشدار در صورت عدم اطمینان
        if (!confidenceResult.isReliable || confidenceResult.isNewLocation) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            confidenceResult.isNewLocation
                                ? '⚠️ احتمالاً در مکان جدیدی هستید!'
                                : '⚠️ ضریب اطمینان پایین است',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (confidenceResult.warningMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        confidenceResult.warningMessage!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    if (confidenceResult.gpsKnnDistance != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'فاصله GPS-KNN: ${confidenceResult.gpsKnnDistance!.toStringAsFixed(0)} متر',
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'مشاهده',
                  textColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      _expandedSignalResults = true;
                    });
                  },
                ),
              ),
            );
          }
        }

        // اگر تخمین قابل اعتماد است، ثبت در history
        if (estimate != null && confidenceResult.isReliable) {
          await _dataLogger.logLocationEstimate(
            deviceId: scanResult.deviceId,
            estimate: estimate,
          );

          await _updateMovementPrediction(scanResult.deviceId);
          
          // به‌روزرسانی مسیر کاربر
          await _loadUserPath();

          _mapController.move(
            LatLng(estimate.latitude, estimate.longitude),
            AppConfig.defaultMapZoom,
          );
        } else {
          setState(() {
            _movementPrediction = null;
          });
        }
      } else {
        // در حالت آموزش، فقط CSV را به‌روزرسانی می‌کنیم
        await AutoCsvService.saveScanToCsv(
          scanResult: scanResult,
          gpsPosition: _currentPosition,
          knnEstimate: null,
          isReliable: null,
          isNewLocation: null,
          gpsKnnDistance: null,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTrainingMode
                  ? 'اسکن انجام شد. ${scanResult.accessPoints.length} شبکه یافت شد.'
                  : 'اسکن با موفقیت انجام شد! ${scanResult.accessPoints.length} شبکه یافت شد.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطا در اسکن: $e\n'
              'لطفاً مطمئن شوید:\n'
              '1. Wi-Fi روشن است\n'
              '2. مجوز Location داده شده است',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _storeRawScan(WifiScanResult scanResult) async {
    try {
      final rawScan = RawWifiScan(
        deviceId: scanResult.deviceId,
        timestamp: scanResult.timestamp,
        readings: scanResult.accessPoints,
        sessionId: _currentSessionId,
        contextId: _currentContext,
      );
      await _database.insertRawWifiScan(rawScan);
    } catch (e) {
      debugPrint('Error storing raw scan: $e');
    }
  }

  /// مدیریت کلیک روی نقشه برای اضافه کردن نقطه مرجع
  Future<void> _handleMapTap(LatLng point) async {
    // نمایش Dialog برای وارد کردن لیبل ناحیه
    final zoneLabel = await showDialog<String>(
      context: context,
      builder: (context) => _buildAddReferencePointDialog(point),
    );

    if (zoneLabel == null) return; // کاربر لغو کرد

    // نمایش Progress
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('در حال اسکن Wi-Fi و ذخیره نقطه مرجع...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _loading = true;
    });

    try {
      await _ensureTrainingSession();
      // انجام اسکن Wi-Fi
      final scanResult = await WifiScanner.performScan();
      await _dataLogger.logWifiScan(scanResult);

      if (scanResult.accessPoints.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هیچ نقطه دسترسی Wi-Fi یافت نشد. لطفاً دوباره تلاش کنید.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // اعتبارسنجی (اگر فعال باشد)
      List<WifiReading> validatedAps = scanResult.accessPoints;
      if (_useValidation) {
        final validationResult = await FingerprintValidator.validateFingerprint(
          latitude: point.latitude,
          longitude: point.longitude,
        );
        
        if (!validationResult.isValid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('اعتبارسنجی ناموفق: ${validationResult.reason}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        validatedAps = validationResult.filteredAccessPoints;
      }

      // ذخیره اثرانگشت با مختصات نقطه کلیک شده
      final validatedScanResult = WifiScanResult(
        deviceId: scanResult.deviceId,
        timestamp: scanResult.timestamp,
        accessPoints: validatedAps,
      );
      
      await _fingerprintService.saveFingerprint(
        latitude: point.latitude,
        longitude: point.longitude,
        zoneLabel: zoneLabel.isEmpty ? null : zoneLabel,
        scanResult: validatedScanResult,
        sessionId: _currentSessionId,
        contextId: _currentContext,
      );

      // به‌روزرسانی لیست نقاط مرجع
      await _loadFingerprintEntries();
      await _updateFingerprintCount();

      // حرکت نقشه به نقطه جدید
      _mapController.move(point, AppConfig.defaultMapZoom);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('نقطه مرجع با ${scanResult.accessPoints.length} AP ذخیره شد!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving reference point: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره نقطه مرجع: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  /// Dialog برای وارد کردن لیبل ناحیه
  Widget _buildAddReferencePointDialog(LatLng point) {
    final zoneController = TextEditingController();
    
    return AlertDialog(
      title: const Text('اضافه کردن نقطه مرجع'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مختصات: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: zoneController,
            decoration: const InputDecoration(
              labelText: 'لیبل ناحیه (اختیاری)',
              hintText: 'مثلاً: اتاق 101، راهرو، سالن',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.label),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'بعد از تأیید، اسکن Wi-Fi انجام می‌شود و داده‌ها ذخیره می‌شوند.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('لغو'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(zoneController.text),
          child: const Text('ذخیره'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _updateMovementPrediction(String deviceId) async {
    final prediction = await _movementPredictionService.predictNextZone(deviceId);
    if (mounted) {
      setState(() {
        _movementPrediction = prediction;
      });
    }
  }

  Future<void> _saveFingerprint() async {
    if (_currentScanResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً ابتدا اسکن را انجام دهید.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final lat = double.tryParse(_latController.text);
    final lon = double.tryParse(_lonController.text);

    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً مختصات معتبر وارد کنید.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // اعتبارسنجی (اگر فعال باشد)
      List<WifiReading> validatedAps = _currentScanResult!.accessPoints;
      if (_useValidation) {
        final validationResult = await FingerprintValidator.validateFingerprint(
          latitude: lat,
          longitude: lon,
        );
        
        if (!validationResult.isValid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('اعتبارسنجی ناموفق: ${validationResult.reason}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        validatedAps = validationResult.filteredAccessPoints;
      }

      // ذخیره با داده‌های validated
      final validatedScanResult = WifiScanResult(
        deviceId: _currentScanResult!.deviceId,
        timestamp: _currentScanResult!.timestamp,
        accessPoints: validatedAps,
      );

      await _ensureTrainingSession();
      await _fingerprintService.saveFingerprint(
        latitude: lat,
        longitude: lon,
        zoneLabel: _zoneController.text.isEmpty ? null : _zoneController.text,
        scanResult: validatedScanResult,
        sessionId: _currentSessionId,
        contextId: _currentContext,
      );

      // پاک کردن فیلدها
      _latController.clear();
      _lonController.clear();
      _zoneController.clear();
      _currentScanResult = null;

      await _updateFingerprintCount();
      await _loadFingerprintEntries();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اثرانگشت با موفقیت ذخیره شد!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving fingerprint: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره اثرانگشت: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
    }
  }

  Future<void> _toggleUseGeolocation(bool value) async {
    await SettingsService.setUseGeolocation(value);
    setState(() {
      _useGeolocation = value;
    });
      }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _motionSub?.cancel();
    _motionService.dispose();
    _latController.dispose();
    _lonController.dispose();
    _zoneController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi KNN Locator'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          // نمایش شناسه دستگاه در AppBar
          if (_deviceId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: Text(
                  'ID: ${PrivacyUtils.shortenMacAddress(_deviceId!, maxLength: 8)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // بخش موقعیت دستگاه
            _buildDeviceLocationSection(),
            const SizedBox(height: 16),
            
            // بخش اسکن Wi-Fi
            _buildWifiScanSection(),
            const SizedBox(height: 16),
            
            // بخش نقشه و نقاط مرجع
            _buildMapSection(),
            const SizedBox(height: 16),
            
            // بخش وضعیت محیط (Indoor/Outdoor)
            if (_unifiedResult != null)
              _buildEnvironmentSection(),
            if (_unifiedResult != null)
              const SizedBox(height: 16),
            
            // بخش نتایج سیگنال‌ها
            _buildSignalResultsSection(),
            const SizedBox(height: 16),
            
            // بخش پیش‌بینی مسیر
            if (_pathPrediction != null && _pathPrediction!.predictedLocations.isNotEmpty)
              _buildPathPredictionSection(),
            if (_pathPrediction != null && _pathPrediction!.predictedLocations.isNotEmpty)
              const SizedBox(height: 16),

            // بخش دیباگ
            _buildDebugPanel(),
            const SizedBox(height: 16),
            
            // بخش تنظیمات
            _buildSettingsSection(),
            const SizedBox(height: 16),
            
            // بخش Researcher Mode
            _buildResearcherModeSection(),
            const SizedBox(height: 16),
            
            // اطلاعات شفافیت
            _buildTransparencyInfo(),
          ],
        ),
      ),
      floatingActionButton: _isTrainingMode
          ? FloatingActionButton.extended(
              onPressed: _saveFingerprint,
              icon: const Icon(Icons.save),
              label: const Text('ذخیره اثرانگشت'),
              backgroundColor: Colors.orange,
            )
          : null,
    );
  }

  Widget _buildMapSection() {
    final referenceMarkers = _fingerprintEntries
        .map(
          (entry) => Marker(
            point: LatLng(entry.latitude, entry.longitude),
            width: 30,
            height: 30,
            child: Tooltip(
              message: entry.zoneLabel ?? entry.fingerprintId,
              child: const Icon(
                Icons.place,
                color: Colors.deepOrange,
                size: 24,
              ),
            ),
          ),
        )
        .toList();

    final estimateMarker = (_locationEstimate != null &&
            _locationEstimate!.isReliable)
        ? [
            Marker(
              point: LatLng(
                _locationEstimate!.latitude,
                _locationEstimate!.longitude,
              ),
              width: 40,
              height: 40,
              child: const Icon(
                Icons.my_location,
                color: Colors.blue,
                size: 32,
              ),
            ),
          ]
        : <Marker>[];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.map, color: Colors.blue.shade700),
        title: const Text(
          'نمایش نقشه و نقاط مرجع',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_fingerprintEntries.length} نقطه مرجع ثبت شده',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        initiallyExpanded: _expandedMap,
        onExpansionChanged: (expanded) {
          setState(() => _expandedMap = expanded);
        },
        children: [
          // راهنمای استفاده و کنترل‌های مسیر
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'برای اضافه کردن نقطه مرجع، روی نقشه کلیک کنید. اسکن Wi-Fi به صورت خودکار انجام می‌شود.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // نمایش اطلاعات مسیر و کنترل نمایش
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: _deviceId != null
                            ? _pathAnalysisService.getPathStatistics(_deviceId!)
                            : Future.value({
                                'total_points': 0,
                                'total_distance_meters': 0.0,
                                'total_time_seconds': 0,
                              }),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }
                          final stats = snapshot.data ?? {
                            'total_points': 0,
                            'total_distance_meters': 0.0,
                            'total_time_seconds': 0,
                          };
                          final distanceKm = (stats['total_distance_meters'] as num) / 1000;
                          final timeHours = (stats['total_time_seconds'] as num) / 3600;
                          
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.route, color: Colors.purple.shade700, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'مسیر حرکت:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.purple.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'طول: ${distanceKm.toStringAsFixed(2)} کیلومتر',
                                  style: TextStyle(fontSize: 11, color: Colors.purple.shade800),
                                ),
                                Text(
                                  'نقاط: ${stats['total_points']}',
                                  style: TextStyle(fontSize: 11, color: Colors.purple.shade800),
                                ),
                                if (timeHours > 0)
                                  Text(
                                    'زمان: ${timeHours.toStringAsFixed(2)} ساعت',
                                    style: TextStyle(fontSize: 11, color: Colors.purple.shade800),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // دکمه نمایش/مخفی کردن مسیر
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showPath = !_showPath;
                        });
                      },
                      icon: Icon(_showPath ? Icons.visibility_off : Icons.visibility),
                      label: Text(_showPath ? 'مخفی کردن مسیر' : 'نمایش مسیر'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
                if (_recentSessions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedTrajectorySessionId ?? _currentSessionId,
                          decoration: const InputDecoration(
                            labelText: 'نمایش مسیر جلسه',
                            border: OutlineInputBorder(),
                          ),
                          items: _recentSessions
                              .map(
                                (session) => DropdownMenuItem(
                                  value: session.sessionId,
                                  child: Text(
                                    '${session.contextId ?? 'بدون زمینه'} - ${session.startedAt.toLocal().toString().substring(0, 16)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _loadTrajectoryForSession(value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'بارگذاری مجدد جلسات',
                        onPressed: _loadContextAndSessions,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            height: 280,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _getInitialMapCenter(),
                  initialZoom: AppConfig.defaultMapZoom,
                  minZoom: AppConfig.minMapZoom,
                  maxZoom: AppConfig.maxMapZoom,
                  onTap: (tapPosition, point) {
                    // کلیک روی نقشه برای اضافه کردن نقطه مرجع
                    _handleMapTap(point);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.wifi_knn_locator',
                  ),
                  // نمایش مسیر کاربر (Polyline)
                  if (_showPath && _userPath.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _userPath
                              .map((entry) => LatLng(entry.latitude, entry.longitude))
                              .toList(),
                          strokeWidth: 3.0,
                          color: Colors.purple,
                          borderStrokeWidth: 1.0,
                          borderColor: Colors.purple.shade300,
                        ),
                      ],
                    ),
                  if (_selectedSessionTrajectory.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _selectedSessionTrajectory
                              .map((entry) => LatLng(entry.latitude, entry.longitude))
                              .toList(),
                          strokeWidth: 3.0,
                          color: Colors.orange.shade700,
                          borderStrokeWidth: 1.0,
                          borderColor: Colors.orange.shade200,
                        ),
                      ],
                    ),
                  // نمایش مسیر حرکت از TrajectoryService
                  if (_trajectory.length > 1)
                    PolylineLayer(
                      polylines: [
                        TrajectoryDisplay.buildTrajectoryPolyline(_trajectory),
                      ],
                    ),
                  // نمایش نقاط مسیر
                  if (_trajectory.isNotEmpty)
                    MarkerLayer(
                      markers: TrajectoryDisplay.buildTrajectoryMarkers(_trajectory),
                    ),
                  // نمایش پیش‌بینی مسیر
                  if (_pathPrediction != null && _pathPrediction!.predictedLocations.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        PredictionDisplay.buildPredictionPolyline(_pathPrediction!),
                      ],
                    ),
                  // نمایش نقاط پیش‌بینی شده
                  if (_pathPrediction != null && _pathPrediction!.predictedLocations.isNotEmpty)
                    MarkerLayer(
                      markers: PredictionDisplay.buildPredictionMarkers(_pathPrediction!),
                    ),
                  if (referenceMarkers.isNotEmpty)
                    MarkerLayer(markers: referenceMarkers),
                  if (estimateMarker.isNotEmpty)
                    MarkerLayer(markers: estimateMarker),
                  if (_currentPosition != null && _useGeolocation)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          width: 30,
                          height: 30,
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.green,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  // نمایش نقطه فعلی روی مسیر (آخرین نقطه)
                  if (_showPath && _userPath.isNotEmpty && _locationEstimate != null && _locationEstimate!.isReliable)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            _locationEstimate!.latitude,
                            _locationEstimate!.longitude,
                          ),
                          width: 35,
                          height: 35,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
                  // راهنمای رنگ‌ها
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLegendItem(Icons.place, Colors.deepOrange, 'نقاط مرجع'),
                          const SizedBox(height: 4),
                          _buildLegendItem(Icons.my_location, Colors.blue, 'تخمین KNN'),
                          if (_showPath && _userPath.length > 1)
                            _buildLegendItem(Icons.route, Colors.purple, 'مسیر حرکت'),
                          if (_showPath && _userPath.isNotEmpty)
                            _buildLegendItem(Icons.location_on, Colors.red, 'موقعیت فعلی'),
                          if (_currentPosition != null && _useGeolocation)
                            _buildLegendItem(Icons.person_pin_circle, Colors.green, 'GPS شما'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildDeviceLocationSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.location_on, color: Colors.blue.shade700),
        title: const Text(
          'موقعیت دستگاه',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: _currentPosition != null
            ? Text(
                '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            : const Text('موقعیت دریافت نشده', style: TextStyle(fontSize: 12)),
        initiallyExpanded: _expandedDeviceLocation,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedDeviceLocation = expanded;
            if (expanded && _currentPosition == null && _useGeolocation) {
              _getDeviceLocation();
            }
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                if (!_useGeolocation)
              Container(
                    padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'استفاده از موقعیت جغرافیایی غیرفعال است. برای فعال کردن به تنظیمات بروید.',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                    ),
                  ],
                ),
                  ),
                if (_useGeolocation) ...[
                  if (_currentPosition != null) ...[
                    _buildInfoRow('عرض جغرافیایی', _currentPosition!.latitude.toStringAsFixed(6)),
                    const SizedBox(height: 8),
                    _buildInfoRow('طول جغرافیایی', _currentPosition!.longitude.toStringAsFixed(6)),
                    const SizedBox(height: 8),
                    _buildInfoRow('دقت', '${_currentPosition!.accuracy.toStringAsFixed(2)} متر'),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loadingLocation ? null : _getDeviceLocation,
                      icon: _loadingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_loadingLocation ? 'در حال دریافت...' : 'به‌روزرسانی موقعیت'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiScanSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.wifi, color: Colors.blue.shade700),
        title: const Text(
          'اسکن Wi-Fi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: _currentScanResult != null
            ? Text(
                '${_currentScanResult!.accessPoints.length} شبکه یافت شد',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            : const Text('هنوز اسکنی انجام نشده', style: TextStyle(fontSize: 12)),
        initiallyExpanded: _expandedWifiScan,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedWifiScan = expanded;
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نمایش شناسه دستگاه
                if (_deviceId != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                child: Row(
                  children: [
                        Icon(Icons.phone_android, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                              const Text(
                                'شناسه دستگاه (هش‌شده):',
                            style: TextStyle(
                                  fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                              const SizedBox(height: 4),
                          Text(
                                PrivacyUtils.shortenMacAddress(_deviceId!, maxLength: 16),
                            style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // دکمه اسکن
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _performScan,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.search),
                    label: Text(_loading ? 'در حال اسکن...' : 'شروع اسکن Wi-Fi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                // حالت آموزش
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('حالت آموزش (Training Mode)'),
                  subtitle: const Text('برای ذخیره اثرانگشت‌ها'),
                  value: _isTrainingMode,
                  onChanged: (value) {
                    setState(() {
                      _isTrainingMode = value;
                      if (value) {
                        _expandedWifiScan = true;
                        _ensureTrainingSession();
                      }
                    });
                  },
                ),
                // فرم آموزش
                if (_isTrainingMode) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'زمینه (Context) و جلسه مسیر',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _currentContext,
                          decoration: const InputDecoration(
                            labelText: 'انتخاب زمینه',
                            border: OutlineInputBorder(),
                          ),
                          items: _availableContexts
                              .map(
                                (ctx) => DropdownMenuItem(
                                  value: ctx,
                                  child: Text(ctx),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _setContext(value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _contextController,
                          decoration: InputDecoration(
                            labelText: 'افزودن زمینه جدید',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                final value = _contextController.text.trim();
                                if (value.isEmpty) return;
                                setState(() {
                                  if (!_availableContexts.contains(value)) {
                                    _availableContexts = [value, ..._availableContexts];
                                  }
                                  _currentContext = value;
                                });
                                _contextController.clear();
                                _startNewSession(contextId: value);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _currentSessionId != null
                                    ? 'جلسه فعال: ${_currentSessionId!.substring(0, 8)}...'
                                    : 'هیچ جلسه فعالی وجود ندارد',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _startNewSession(),
                              icon: const Icon(Icons.fiber_new),
                              label: const Text('جلسه جدید'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: 'عرض جغرافیایی (Latitude)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.explore),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lonController,
                    decoration: const InputDecoration(
                      labelText: 'طول جغرافیایی (Longitude)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.explore),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _zoneController,
                    decoration: const InputDecoration(
                      labelText: 'لیبل ناحیه (اختیاری)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                  ),
                ],
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSignalResultsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.signal_cellular_alt, color: Colors.blue.shade700),
        title: const Text(
          'نتایج سیگنال‌ها',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: _currentScanResult != null
            ? Text(
                '${_currentScanResult!.accessPoints.length} نقطه دسترسی',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            : const Text('هیچ نتیجه‌ای وجود ندارد', style: TextStyle(fontSize: 12)),
        initiallyExpanded: _expandedSignalResults,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedSignalResults = expanded;
          });
        },
                  children: [
          Padding(
            padding: const EdgeInsets.all(16),
                        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                // نمایش هشدار عدم اطمینان
                if (_confidenceResult != null && (!_confidenceResult!.isReliable || _confidenceResult!.isNewLocation)) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _confidenceResult!.isNewLocation
                                    ? '⚠️ احتمالاً در مکان جدیدی هستید!'
                                    : '⚠️ ضریب اطمینان پایین است',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_confidenceResult!.warningMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _confidenceResult!.warningMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                        if (_confidenceResult!.gpsKnnDistance != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.straighten, color: Colors.orange.shade700, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'فاصله GPS و KNN: ${_confidenceResult!.gpsKnnDistance!.toStringAsFixed(0)} متر',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '💡 پیشنهاد: اگر در مکان جدیدی هستید، می‌توانید در حالت آموزش (Training Mode) اثرانگشت جدیدی ثبت کنید.',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // نمایش موقعیت تخمینی
                if (_locationEstimate != null && _locationEstimate!.isReliable) ...[
                  Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                        colors: [Colors.green.shade400, Colors.green.shade600],
                                  ),
                      borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                            const Icon(Icons.location_on, color: Colors.white),
                                        const SizedBox(width: 8),
                                        const Text(
                              'موقعیت تخمینی',
                                          style: TextStyle(
                                            color: Colors.white,
                                fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                        _buildInfoRowWhite('عرض جغرافیایی', _locationEstimate!.latitude.toStringAsFixed(6)),
                        const SizedBox(height: 8),
                        _buildInfoRowWhite('طول جغرافیایی', _locationEstimate!.longitude.toStringAsFixed(6)),
                        const SizedBox(height: 8),
                        _buildInfoRowWhite(
                          'ضریب اطمینان',
                          '${(_locationEstimate!.confidence * 100).toStringAsFixed(1)}%',
                                      ),
                        if (_locationEstimate!.zoneLabel != null) ...[
                                      const SizedBox(height: 8),
                          _buildInfoRowWhite('ناحیه', _locationEstimate!.zoneLabel!),
                        ],
                      ],
                    ),
                                      ),
                  const SizedBox(height: 16),
                  if (_movementPrediction != null &&
                      _movementPrediction!.hasPrediction)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.trending_up,
                              color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'پیش‌بینی حرکت بعدی (Markov)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ناحیه احتمالی: ${_movementPrediction!.predictedZone}',
                                  style: TextStyle(
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                Text(
                                  'اعتماد: ${(100 * _movementPrediction!.probability).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_movementPrediction == null ||
                      !_movementPrediction!.hasPrediction) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'برای پیش‌بینی حرکت، ابتدا چند تخمین موقعیت معتبر ثبت کنید.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ] else if (_locationEstimate != null && !_locationEstimate!.isReliable) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                                          ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ضریب اطمینان پایین است. لطفاً اسکن را تکرار کنید.',
                            style: TextStyle(color: Colors.orange.shade900),
                                          ),
                                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // لیست APها
                if (_currentScanResult != null && _currentScanResult!.accessPoints.isNotEmpty) ...[
                                      const Text(
                    'نقاط دسترسی Wi-Fi:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ..._currentScanResult!.accessPoints.map((ap) => _buildAccessPointItem(ap)),
                ] else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.wifi_off, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'هنوز اسکنی انجام نشده',
                            style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                  ],
                                ),
                              ),
                            ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _calculateApOverlap(FingerprintEntry fingerprint) {
    if (_currentScanResult == null) return 0;
    final currentSet = _currentScanResult!.accessPoints.map((ap) => ap.bssid).toSet();
    final fpSet = fingerprint.accessPoints.map((ap) => ap.bssid).toSet();
    return currentSet.intersection(fpSet).length;
  }

  /// بخش نمایش وضعیت محیط (Indoor/Outdoor/Hybrid)
  Widget _buildEnvironmentSection() {
    if (_unifiedResult == null) return const SizedBox.shrink();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_searching, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                const Text(
                  'وضعیت محیط',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // نمایش وضعیت محیط
            EnvironmentIndicator(
              environmentType: _unifiedResult!.environmentType,
              confidence: _unifiedResult!.confidence,
            ),
            const SizedBox(height: 12),
            // اطلاعات تفصیلی
            if (_unifiedResult!.indoorResult != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Wi-Fi: ${_unifiedResult!.indoorResult!.accessPointCount} AP، '
                      'قدرت: ${(_unifiedResult!.indoorResult!.wifiStrength * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_unifiedResult!.outdoorResult != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.signal_cellular_alt, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Cell: ${_unifiedResult!.outdoorResult!.cellTowerCount} دکل، '
                      'میانگین سیگنال: ${_unifiedResult!.outdoorResult!.averageSignalStrength.toStringAsFixed(0)} dBm',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// بخش نمایش پیش‌بینی مسیر
  Widget _buildPathPredictionSection() {
    if (_pathPrediction == null || _pathPrediction!.predictedLocations.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'پیش‌بینی مسیر',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // نمایش اطلاعات پیش‌بینی
            PredictionDisplay.buildPredictionInfo(_pathPrediction!),
            const SizedBox(height: 12),
            // نمایش نقاط پیش‌بینی شده
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'نقاط پیش‌بینی شده:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ..._pathPrediction!.predictedLocations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final location = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '(${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)})',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ),
                          Text(
                            '${(location.confidence * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    if (_locationEstimate == null || _currentScanResult == null) {
      return const SizedBox.shrink();
    }

    final neighbors = _locationEstimate!.nearestNeighbors;
    if (neighbors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.bug_report, color: Colors.red.shade700),
        initiallyExpanded: false,
        title: const Text(
          'دیباگ KNN و همپوشانی AP',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'میانگین فاصله: ${_locationEstimate!.averageDistance.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: neighbors.length,
                  itemBuilder: (context, index) {
                    final neighbor = neighbors[index];
                    final overlap = _calculateApOverlap(neighbor);
                    final avgRssi = neighbor.accessPoints.isNotEmpty
                        ? (neighbor.accessPoints
                                .map((ap) => ap.rssi)
                                .reduce((a, b) => a + b) /
                            neighbor.accessPoints.length)
                        : 0.0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(neighbor.zoneLabel ?? neighbor.fingerprintId),
                      subtitle: Text(
                        'همپوشانی AP: $overlap | میانگین RSSI: ${avgRssi.toStringAsFixed(1)} dBm | زمان: ${neighbor.createdAt.toLocal().toString().substring(11, 19)}',
                      ),
                      trailing: Text(
                        '${_calculateApOverlap(neighbor)} AP',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessPointItem(WifiReading ap) {
    final signalStrength = _getSignalStrength(ap.rssi);
    final signalColor = _getSignalColor(ap.rssi);
    final maskedBssid = PrivacyUtils.maskMacAddress(ap.bssid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
                                ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: signalColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.wifi, color: signalColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                          Text(
                  maskedBssid,
                  style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                if (ap.ssid != null && ap.ssid!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'SSID: ${ap.ssid}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.signal_cellular_alt, size: 16, color: signalColor),
                    const SizedBox(width: 4),
                    Text(
                      '${ap.rssi} dBm',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(width: 12),
                                            Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                        color: signalColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                        signalStrength,
                                                style: TextStyle(
                          fontSize: 10,
                          color: signalColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                    if (ap.frequency != null) ...[
                      const Spacer(),
                                                    Text(
                        '${ap.frequency} MHz',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
    );
  }

  Widget _buildSettingsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.settings, color: Colors.blue.shade700),
        title: const Text(
          'تنظیمات',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        initiallyExpanded: _expandedSettings,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedSettings = expanded;
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('استفاده از موقعیت جغرافیایی'),
                  subtitle: const Text(
                    'برای بهبود دقت تخمین موقعیت، از GPS استفاده می‌شود',
                  ),
                  value: _useGeolocation,
                  onChanged: _toggleUseGeolocation,
                  secondary: Icon(
                    _useGeolocation ? Icons.location_on : Icons.location_off,
                    color: _useGeolocation ? Colors.green : Colors.grey,
                  ),
                                              ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('تعداد اثرانگشت‌ها'),
                  trailing: Text(
                    '$_fingerprintCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
        ],
      ),
    );
  }

  Widget _buildResearcherModeSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.science, color: Colors.purple.shade700),
        title: const Text(
          'حالت پژوهشگر (Researcher Mode)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'ابزارهای تحلیل و Export داده‌ها',
          style: TextStyle(fontSize: 12),
        ),
        initiallyExpanded: _expandedResearcherMode,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedResearcherMode = expanded;
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // نمایش اطلاعات CSV خودکار
                FutureBuilder<Map<String, dynamic>>(
                  future: _getAutoCsvInfo(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final info = snapshot.data!;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.file_copy, color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'CSV خودکار (Auto CSV)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'تعداد اسکن‌ها: ${info['row_count']}',
                              style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                            ),
                            if (info['file_size'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'اندازه فایل: ${(info['file_size'] / 1024).toStringAsFixed(2)} KB',
                                style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '💡 در هر اسکن Wi-Fi، داده‌ها به صورت خودکار در CSV ذخیره می‌شوند.',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 16),
                // Export Data
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exportAutoCsv,
                    icon: const Icon(Icons.download),
                    label: const Text('دانلود CSV خودکار'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exportData,
                    icon: const Icon(Icons.download),
                    label: const Text('Export تمام داده‌ها (CSV)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exportDataJson,
                    icon: const Icon(Icons.code),
                    label: const Text('Export تمام داده‌ها (JSON)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapReferencePointPicker(
                            fingerprintService: _fingerprintService,
                            sessionId: _currentSessionId,
                            contextId: _currentContext,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('انتخاب نقطه مرجع روی نقشه'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const Divider(),
                // Statistics
                FutureBuilder<Map<String, dynamic>>(
                  future: _dataExportService.getStatistics(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData) {
                      return const Text('خطا در دریافت آمار');
                    }
                    final stats = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'آمار داده‌ها:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStatRow('تعداد Fingerprintها', stats['total_fingerprints'].toString()),
                        _buildStatRow('تعداد اسکن‌های Wi-Fi', stats['total_wifi_scans'].toString()),
                        _buildStatRow('تعداد تخمین موقعیت', stats['total_location_estimates'].toString()),
                        _buildStatRow('BSSIDهای یکتا', stats['unique_bssids'].toString()),
                        _buildStatRow(
                          'میانگین Confidence',
                          '${((stats['average_confidence'] as double) * 100).toStringAsFixed(1)}%',
                        ),
                      ],
                    );
                  },
                ),
                const Divider(),
                // Validation Toggle
                SwitchListTile(
                  title: const Text('استفاده از Validation'),
                  subtitle: const Text(
                    'اعتبارسنجی خودکار اثرانگشت‌ها (چند اسکن + بررسی همگرایی)',
                  ),
                  value: _useValidation,
                  onChanged: (value) {
                    setState(() {
                      _useValidation = value;
                    });
                  },
                  secondary: Icon(
                    _useValidation ? Icons.verified : Icons.verified_user_outlined,
                    color: _useValidation ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// دریافت اطلاعات CSV خودکار
  Future<Map<String, dynamic>> _getAutoCsvInfo() async {
    try {
      final rowCount = await AutoCsvService.getCsvRowCount();
      final fileSize = await AutoCsvService.getCsvFileSize();
      return {
        'row_count': rowCount,
        'file_size': fileSize ?? 0,
      };
    } catch (e) {
      return {'row_count': 0, 'file_size': 0};
    }
  }

  /// دانلود CSV خودکار
  Future<void> _exportAutoCsv() async {
    try {
      setState(() => _loading = true);
      final filePath = await AutoCsvService.getCsvFilePath();
      
      if (filePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فایل CSV خودکار وجود ندارد یا هنوز اسکنی انجام نشده است.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فایل CSV خودکار پیدا نشد.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final savedPath = await AutoCsvService.saveCsvToDownloadsAndOpen();
      if (savedPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ذخیره فایل در پوشه Downloads با مشکل مواجه شد.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فایل CSV در پوشه Downloads ذخیره شد.\n$savedPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دانلود CSV خودکار: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportData() async {
    try {
      setState(() => _loading = true);
      // دانلود و اشتراک‌گذاری فایل CSV
      await _dataExportService.downloadAndShareCsv();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فایل CSV آماده دانلود است! لطفاً از منوی اشتراک‌گذاری استفاده کنید.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در Export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportDataJson() async {
    try {
      setState(() => _loading = true);
      final filePath = await _dataExportService.exportAllDataToJson();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('داده‌ها با موفقیت Export شدند!\n$filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در Export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildTransparencyInfo() {
    return Card(
      elevation: 2,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'شفافیت و حریم خصوصی',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                            ),
                          ],
                        ),
            const SizedBox(height: 12),
            Text(
              'این اپلیکیشن از موقعیت دستگاه (GPS) و سیگنال‌های Wi-Fi اطراف برای تخمین موقعیت شما استفاده می‌کند. '
              'شناسه دستگاه شما به صورت هش‌شده ذخیره می‌شود و MAC addressهای روترها به صورت جزئی نمایش داده می‌شوند.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade900,
                height: 1.5,
              ),
                            ),
            const SizedBox(height: 8),
            if (_useGeolocation)
              Container(
                padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade200),
                                          ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'استفاده از موقعیت جغرافیایی فعال است',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                          ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'استفاده از موقعیت جغرافیایی غیرفعال است',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRowWhite(String label, String value) {
    return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                label,
                  style: const TextStyle(
                        fontSize: 12,
                  color: Colors.white70,
                      ),
                    ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                          fontWeight: FontWeight.bold,
                  color: Colors.white,
                      ),
                ),
              ],
            ),
          ),
        ],
    );
  }

  String _getSignalStrength(int rssi) {
    if (rssi >= AppConfig.excellentRssi) return 'عالی';
    if (rssi >= AppConfig.goodRssi) return 'خوب';
    if (rssi >= AppConfig.fairRssi) return 'متوسط';
    if (rssi >= AppConfig.poorRssi) return 'ضعیف';
    return 'خیلی ضعیف';
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= AppConfig.excellentRssi) return Colors.green;
    if (rssi >= AppConfig.goodRssi) return Colors.lightGreen;
    if (rssi >= AppConfig.fairRssi) return Colors.orange;
    if (rssi >= AppConfig.poorRssi) return Colors.deepOrange;
    return Colors.red;
  }

  LatLng _getInitialMapCenter() {
    if (_locationEstimate != null && _locationEstimate!.isReliable) {
      return LatLng(_locationEstimate!.latitude, _locationEstimate!.longitude);
    }
    if (_fingerprintEntries.isNotEmpty) {
      final first = _fingerprintEntries.first;
      return LatLng(first.latitude, first.longitude);
    }
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    return LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude);
  }
}
