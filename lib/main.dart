import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'config.dart';
import 'data_model.dart';
import 'wifi_scanner.dart';
import 'local_database.dart';
import 'knn_localization.dart';
import 'services/fingerprint_service.dart';
import 'services/location_service.dart';
import 'services/settings_service.dart';
import 'utils/privacy_utils.dart';

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
  Position? _currentPosition;
  String? _deviceId;
  int _fingerprintCount = 0;
  bool _useGeolocation = true;
  bool _loadingLocation = false;
  
  // Expansion states
  bool _expandedDeviceLocation = false;
  bool _expandedWifiScan = false;
  bool _expandedSignalResults = false;
  bool _expandedSettings = false;
  
  // Services
  late final LocalDatabase _database;
  late final KnnLocalization _knnLocalization;
  late final FingerprintService _fingerprintService;
  
  // UI Controllers
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();
  final TextEditingController _zoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _database = LocalDatabase.instance;
    _knnLocalization = KnnLocalization(_database);
    _fingerprintService = FingerprintService(_database);
    
    // دریافت شناسه دستگاه
    _deviceId = await PrivacyUtils.getDeviceId();
    
    // بارگذاری تنظیمات
    _useGeolocation = await SettingsService.getUseGeolocation();
    
    // بارگذاری تعداد اثرانگشت‌ها
    _updateFingerprintCount();
    
    setState(() {});
  }

  Future<void> _updateFingerprintCount() async {
    _fingerprintCount = await _fingerprintService.getFingerprintCount();
    if (mounted) setState(() {});
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
    });

    try {
      // اجرای اسکن
      final scanResult = await WifiScanner.performScan();
      
      setState(() {
        _currentScanResult = scanResult;
        _expandedSignalResults = true; // باز کردن بخش نتایج
      });

      // اگر در حالت آموزش نیستیم، تخمین موقعیت انجام می‌دهیم
      if (!_isTrainingMode) {
        final estimate = await _knnLocalization.estimateLocation(
          scanResult,
          k: AppConfig.defaultK,
        );

        setState(() {
          _locationEstimate = estimate;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isTrainingMode
                ? 'اسکن انجام شد. اکنون مختصات را وارد کنید.'
                : 'اسکن با موفقیت انجام شد!'),
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
            content: Text('خطا در اسکن: $e'),
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
      await _fingerprintService.saveFingerprint(
        latitude: lat,
        longitude: lon,
        zoneLabel: _zoneController.text.isEmpty ? null : _zoneController.text,
        scanResult: _currentScanResult,
      );

      // پاک کردن فیلدها
      _latController.clear();
      _lonController.clear();
      _zoneController.clear();
      _currentScanResult = null;

      await _updateFingerprintCount();

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
    _latController.dispose();
    _lonController.dispose();
    _zoneController.dispose();
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
            
            // بخش نتایج سیگنال‌ها
            _buildSignalResultsSection(),
            const SizedBox(height: 16),
            
            // بخش تنظیمات
            _buildSettingsSection(),
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
                      }
                    });
                  },
                ),
                // فرم آموزش
                if (_isTrainingMode) ...[
                  const SizedBox(height: 16),
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
                  leading: const Icon(Icons.database),
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
}
