import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'data_model.dart';
import 'wifi_scanner.dart';
import 'local_database.dart';
import 'knn_localization.dart';
import 'services/fingerprint_service.dart';
import 'utils/privacy_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  String? _deviceId;
  int _fingerprintCount = 0;
  
  // Services
  late final LocalDatabase _database;
  late final KnnLocalization _knnLocalization;
  late final FingerprintService _fingerprintService;
  
  // UI Controllers
  final MapController _mapController = MapController();
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
    
    // بارگذاری تعداد اثرانگشت‌ها
    _updateFingerprintCount();
    
    setState(() {});
  }

  Future<void> _updateFingerprintCount() async {
    _fingerprintCount = await _fingerprintService.getFingerprintCount();
    if (mounted) setState(() {});
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

        // به‌روزرسانی نقشه
        if (estimate != null && estimate.isReliable) {
          _mapController.move(
            LatLng(estimate.latitude, estimate.longitude),
            AppConfig.defaultMapZoom,
          );
        }
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

  Future<void> _openInExternalMaps(double lat, double lon) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در باز کردن نقشه: $e')),
        );
      }
    }
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
    final defaultLocation = LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude);
    final predictionLocation = _locationEstimate != null
        ? LatLng(_locationEstimate!.latitude, _locationEstimate!.longitude)
        : defaultLocation;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.blue.shade100,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              _buildAppBar(),
              
              // Main Content
              Expanded(
                child: Row(
                  children: [
                    // Left Panel - Info
                    Expanded(
                      flex: 1,
                      child: _buildLeftPanel(),
                    ),
                    
                    // Right Panel - Map
                    Expanded(
                      flex: 2,
                      child: _buildMapPanel(predictionLocation),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.wifi_find, color: Colors.blue.shade700, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WiFi KNN Locator',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    Text(
                      'موقعیت‌یابی با الگوریتم KNN',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // نمایش شناسه دستگاه
              if (_deviceId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'شناسه دستگاه:',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        PrivacyUtils.shortenMacAddress(_deviceId!, maxLength: 12),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
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
                label: Text(_loading ? 'در حال اسکن...' : 'اسکن WiFi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Toggle Training Mode
          Row(
            children: [
              Switch(
                value: _isTrainingMode,
                onChanged: (value) {
                  setState(() {
                    _isTrainingMode = value;
                    if (!value) {
                      _latController.clear();
                      _lonController.clear();
                      _zoneController.clear();
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(
                'حالت آموزش (Training Mode)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _isTrainingMode ? Colors.green.shade700 : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text(
                'تعداد اثرانگشت‌ها: $_fingerprintCount',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Prediction/Training Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isTrainingMode
                      ? [Colors.orange.shade600, Colors.orange.shade800]
                      : [Colors.blue.shade600, Colors.blue.shade800],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _isTrainingMode
                  ? _buildTrainingCard()
                  : _buildPredictionCard(),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Networks Card
          Expanded(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: _buildNetworksCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            const Text(
              'موقعیت برآورد شده',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_locationEstimate != null && _locationEstimate!.isReliable) ...[
          _buildInfoRow('عرض جغرافیایی', _locationEstimate!.latitude.toStringAsFixed(6), Icons.explore),
          const SizedBox(height: 8),
          _buildInfoRow('طول جغرافیایی', _locationEstimate!.longitude.toStringAsFixed(6), Icons.explore),
          const SizedBox(height: 8),
          _buildInfoRow(
            'ضریب اطمینان',
            '${(_locationEstimate!.confidence * 100).toStringAsFixed(1)}%',
            Icons.verified,
          ),
          if (_locationEstimate!.zoneLabel != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow('ناحیه', _locationEstimate!.zoneLabel!, Icons.place),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openInExternalMaps(
                _locationEstimate!.latitude,
                _locationEstimate!.longitude,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('باز کردن در Google Maps'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
              ),
            ),
          ),
        ] else if (_locationEstimate != null && !_locationEstimate!.isReliable) ...[
          const Text(
            'ضریب اطمینان پایین است. لطفاً اسکن را تکرار کنید.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ] else
          const Text(
            'برای مشاهده موقعیت، ابتدا اسکن را انجام دهید',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
      ],
    );
  }

  Widget _buildTrainingCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.school, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            const Text(
              'ذخیره اثرانگشت',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _latController,
          decoration: const InputDecoration(
            labelText: 'عرض جغرافیایی (Latitude)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lonController,
          decoration: const InputDecoration(
            labelText: 'طول جغرافیایی (Longitude)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _zoneController,
          decoration: const InputDecoration(
            labelText: 'لیبل ناحیه (اختیاری)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saveFingerprint,
            icon: const Icon(Icons.save),
            label: const Text('ذخیره اثرانگشت'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.orange.shade800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworksCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.wifi, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            Text(
              'شبکه‌های یافت شده',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
            const Spacer(),
            if (_currentScanResult != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentScanResult!.accessPoints.length}',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _currentScanResult == null || _currentScanResult!.accessPoints.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'هنوز اسکنی انجام نشده',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _currentScanResult!.accessPoints.length,
                  itemBuilder: (context, index) {
                    final ap = _currentScanResult!.accessPoints[index];
                    return _buildNetworkItem(ap);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNetworkItem(WifiReading network) {
    final signalStrength = _getSignalStrength(network.rssi);
    final signalColor = _getSignalColor(network.rssi);
    final maskedBssid = PrivacyUtils.maskMacAddress(network.bssid);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      ),
                    ),
                    if (network.ssid != null && network.ssid!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'SSID: ${network.ssid}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.signal_cellular_alt, size: 16, color: signalColor),
              const SizedBox(width: 4),
              Text(
                '${network.rssi} dBm',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              if (network.frequency != null) ...[
                const Spacer(),
                Text(
                  '${network.frequency} MHz',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapPanel(LatLng centerLocation) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: centerLocation,
            initialZoom: AppConfig.defaultMapZoom,
            minZoom: AppConfig.minMapZoom,
            maxZoom: AppConfig.maxMapZoom,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.wifi_knn_locator',
            ),
            if (_locationEstimate != null && _locationEstimate!.isReliable)
              MarkerLayer(
                markers: [
                  Marker(
                    point: centerLocation,
                    width: 80,
                    height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 40),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
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
