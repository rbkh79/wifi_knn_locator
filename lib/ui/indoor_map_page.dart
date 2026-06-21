import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:uuid/uuid.dart';

import '../services/indoor_csv_manager.dart';
import '../cell_scanner.dart';
import '../wifi_scanner.dart';
import '../data_model.dart';

/// صفحه Indoor Mapping برای انتخاب Ground Truth و جمع‌آوری Fingerprint
class IndoorMapPage extends StatefulWidget {
  const IndoorMapPage({super.key});

  @override
  State<IndoorMapPage> createState() => _IndoorMapPageState();
}

class _IndoorMapPageState extends State<IndoorMapPage> {
  // Map Controller
  final MapController _mapController = MapController();
  
  // موقعیت اولیه نقشه (دانشگاه فردوسی مشهد)
  static const double _initialLatitude = 36.3345;
  static const double _initialLongitude = 59.6395;
  static const double _initialZoom = 18.0;
  
  // موقعیت انتخاب‌شده
  LatLng? _selectedLocation;
  Marker? _selectedMarker;
  
  // فیلدهای Ground Truth
  final TextEditingController _buildingController = TextEditingController();
  final TextEditingController _floorController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _referencePointIdController = TextEditingController();
  
  // WiFi و BTS Scanner
  WifiScanResult? _wifiScanResult;
  CellScanResult? _cellScanResult;
  Position? _gpsPosition;
  bool _isScanning = false;
  
  // آمار
  int _totalReferencePoints = 0;
  int _totalSamples = 0;
  Map<String, int> _samplesPerReferencePoint = {};
  
  // لیست نقاط ذخیره‌شده
  List<Map<String, dynamic>> _savedPoints = [];
  
  @override
  void initState() {
    super.initState();
    _loadSavedPoints();
    _loadStatistics();
  }
  
  @override
  void dispose() {
    _buildingController.dispose();
    _floorController.dispose();
    _roomController.dispose();
    _referencePointIdController.dispose();
    super.dispose();
  }
  
  /// بارگذاری نقاط ذخیره‌شده
  Future<void> _loadSavedPoints() async {
    final points = await IndoorCsvManager.loadOsmPoints();
    setState(() {
      _savedPoints = points;
    });
  }
  
  /// بارگذاری آمار
  Future<void> _loadStatistics() async {
    final stats = await IndoorCsvManager.loadStatistics();
    setState(() {
      _totalReferencePoints = stats['totalReferencePoints'] as int? ?? 0;
      _totalSamples = stats['totalSamples'] as int? ?? 0;
      _samplesPerReferencePoint = stats['samplesPerReferencePoint'] as Map<String, int>? ?? {};
    });
  }
  
  /// اسکن WiFi و BTS
  Future<void> _scanWifiAndBts() async {
    setState(() => _isScanning = true);
    
    try {
      // اسکن WiFi
      final wifiResult = await _scanWifi();
      
      // اسکن BTS
      final cellResult = await _scanBts();
      
      // اسکن GPS
      final gpsResult = await _scanGps();
      
      setState(() {
        _wifiScanResult = wifiResult;
        _cellScanResult = cellResult;
        _gpsPosition = gpsResult;
      });
    } catch (e) {
      debugPrint('Error scanning: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در اسکن: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isScanning = false);
    }
  }
  
  /// اسکن WiFi
  Future<WifiScanResult> _scanWifi() async {
    return await WifiScanner.performScan();
  }
  
  /// اسکن BTS
  Future<CellScanResult> _scanBts() async {
    return await CellScanner.performScan();
  }
  
  /// اسکن GPS
  Future<Position> _scanGps() async {
    final hasPermission = await Permission.location.isGranted;
    if (!hasPermission) {
      await Permission.location.request();
    }
    
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
  
  /// دریافت Device ID
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String deviceId = prefs.getString('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }
  
  /// ذخیره Ground Truth
  Future<void> _saveGroundTruth() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً یک نقطه روی نقشه انتخاب کنید'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    if (_buildingController.text.isEmpty ||
        _floorController.text.isEmpty ||
        _roomController.text.isEmpty ||
        _referencePointIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً تمام فیلدها را پر کنید'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    try {
      final point = {
        'Timestamp': DateTime.now().toIso8601String(),
        'Latitude': _selectedLocation!.latitude,
        'Longitude': _selectedLocation!.longitude,
        'Building': _buildingController.text,
        'Floor': _floorController.text,
        'Room': _roomController.text,
        'ReferencePointID': _referencePointIdController.text,
        'Source': 'OSM_CLICK',
      };
      
      await IndoorCsvManager.saveOsmPoint(point);
      
      setState(() {
        _savedPoints.add(point);
      });
      
      await _loadStatistics();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Ground Truth ذخیره شد'), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('Error saving ground truth: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در ذخیره: $e'), backgroundColor: Colors.red),
      );
    }
  }
  
  /// ذخیره Fingerprint
  Future<void> _saveFingerprint() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً یک نقطه روی نقشه انتخاب کنید'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    if (_wifiScanResult == null || _cellScanResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً ابتدا WiFi و BTS را اسکن کنید'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    if (_buildingController.text.isEmpty ||
        _floorController.text.isEmpty ||
        _roomController.text.isEmpty ||
        _referencePointIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً تمام فیلدها را پر کنید'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    try {
      // دریافت SampleID خودکار
      final sampleId = await IndoorCsvManager.getNextSampleId(_referencePointIdController.text);
      
      // ذخیره Fingerprint برای هر WiFi Access Point
      for (final ap in _wifiScanResult!.accessPoints) {
        final fingerprint = {
          'SampleID': sampleId,
          'ReferencePointID': _referencePointIdController.text,
          'Timestamp': DateTime.now().toIso8601String(),
          'Latitude': _selectedLocation!.latitude,
          'Longitude': _selectedLocation!.longitude,
          'Building': _buildingController.text,
          'Floor': _floorController.text,
          'Room': _roomController.text,
          'CellID': _cellScanResult!.servingCell?.cellId ?? '',
          'TAC': _cellScanResult!.servingCell?.tac ?? '',
          'PCI': _cellScanResult!.servingCell?.pci ?? '',
          'CellSignal': _cellScanResult!.servingCell?.signalStrength ?? '',
          'NetworkType': _cellScanResult!.servingCell?.networkType ?? '',
          'WifiBSSID': ap.bssid,
          'WifiSSID': ap.ssid ?? '',
          'WifiRSSI': ap.rssi,
          'WifiFrequency': ap.frequency ?? '',
          'GPS_Latitude': _gpsPosition?.latitude ?? '',
          'GPS_Longitude': _gpsPosition?.longitude ?? '',
          'GPS_Accuracy': _gpsPosition?.accuracy ?? '',
          'Source': 'OSM_CLICK',
        };
        
        await IndoorCsvManager.saveFingerprint(fingerprint);
      }
      
      await _loadStatistics();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Fingerprint ذخیره شد (SampleID: $sampleId)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Error saving fingerprint: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در ذخیره: $e'), backgroundColor: Colors.red),
      );
    }
  }
  
  /// انتخاب نقطه روی نقشه
  void _onMapTap(LatLng point) {
    setState(() {
      _selectedLocation = point;
      _selectedMarker = Marker(
        point: point,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.location_on, color: Colors.white, size: 24),
        ),
      );
    });
    
    _mapController.move(point, _initialZoom);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Mapping'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // نقشه
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(_initialLatitude, _initialLongitude),
                initialZoom: _initialZoom,
                onTap: (tapPosition, point) => _onMapTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.example.wifi_knn_locator',
                ),
                MarkerLayer(
                  markers: [
                    if (_selectedMarker != null) _selectedMarker!,
                    ..._savedPoints.map((point) => Marker(
                      point: LatLng(point['Latitude'], point['Longitude']),
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    )),
                  ],
                ),
              ],
            ),
          ),
          
          // اطلاعات مختصات
          if (_selectedLocation != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.blue.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}'),
                  Text('Lon: ${_selectedLocation!.longitude.toStringAsFixed(6)}'),
                ],
              ),
            ),
          
          // فیلدهای Ground Truth
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buildingController,
                          decoration: const InputDecoration(
                            labelText: 'Building',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _floorController,
                          decoration: const InputDecoration(
                            labelText: 'Floor',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _roomController,
                          decoration: const InputDecoration(
                            labelText: 'Room',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _referencePointIdController,
                          decoration: const InputDecoration(
                            labelText: 'Reference Point ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // دکمه‌های اسکن
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isScanning ? null : _scanWifiAndBts,
                          icon: const Icon(Icons.scanner),
                          label: const Text('اسکن WiFi & BTS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveGroundTruth,
                          icon: const Icon(Icons.save),
                          label: const Text('ذخیره Ground Truth'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _saveFingerprint,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('ذخیره Fingerprint'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  
                  // آمار
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('آمار:', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('تعداد Reference Point: $_totalReferencePoints'),
                          Text('تعداد کل نمونه‌ها: $_totalSamples'),
                          const SizedBox(height: 8),
                          if (_samplesPerReferencePoint.isNotEmpty)
                            ..._samplesPerReferencePoint.entries.map((entry) =>
                              Text('${entry.key}: ${entry.value} نمونه'),
                            ),
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
}
