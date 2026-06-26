import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;

import '../services/indoor_csv_manager.dart';
import '../cell_scanner.dart';
import '../wifi_scanner.dart';
import '../data_model.dart';

/// مدل یک Feature اتاق/کلاس از GeoJSON
class _RoomFeature {
  final String? name;
  final String? ref;
  final String indoor; // room | corridor | ...
  final List<LatLng> points;

  _RoomFeature({
    required this.name,
    required this.ref,
    required this.indoor,
    required this.points,
  });

  /// برچسب نمایشی روی نقشه: ترجیحاً "ref — name"
  String get displayLabel {
    final parts = <String>[];
    if (ref != null && ref!.trim().isNotEmpty) parts.add(ref!.trim());
    if (name != null && name!.trim().isNotEmpty) parts.add(name!.trim());
    return parts.join(' — ');
  }

  /// مقداری که در فیلد Room فرم قرار می‌گیرد
  String get roomValue {
    if (ref != null && ref!.trim().isNotEmpty) return ref!.trim();
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    return '';
  }
}

/// صفحه Indoor Mapping برای انتخاب Ground Truth و جمع‌آوری Fingerprint
class IndoorMapPage extends StatefulWidget {
  const IndoorMapPage({super.key});

  @override
  State<IndoorMapPage> createState() => _IndoorMapPageState();
}

class _IndoorMapPageState extends State<IndoorMapPage> {
  // Map Controller
  final MapController _mapController = MapController();

  // موقعیت اولیه نقشه (دانشکده مهندسی دانشگاه فردوسی مشهد)
  static const double _initialLatitude = 36.3124;
  static const double _initialLongitude = 59.5265;
  static const double _initialZoom = 19.0;

  // موقعیت انتخاب‌شده
  LatLng? _selectedLocation;
  Marker? _selectedMarker;

  // انتخاب طبقه
  int _selectedLevel = 0;
  final List<int> _availableLevels = [-1, 0, 1, 2, 3];

  // Featureهای لودشده از GeoJSON (همراه با نام اتاق)
  List<_RoomFeature> _roomFeatures = [];
  // فقط اتاق/کلاس‌ها (برای tap-to-fill)
  List<_RoomFeature> _roomsOnly = [];
  bool _showLabels = true;

  // Notifier برای تشخیص tap روی پلیگان اتاق
  final LayerHitNotifier<_RoomFeature> _polygonHitNotifier =
      ValueNotifier<LayerHitResult<_RoomFeature>?>(null);

  // فیلدهای Ground Truth
  final TextEditingController _buildingController = TextEditingController();
  final TextEditingController _floorController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _referencePointIdController =
      TextEditingController();

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
    _loadGeoJson();
    _polygonHitNotifier.addListener(_onPolygonHit);
  }

  @override
  void dispose() {
    _polygonHitNotifier.removeListener(_onPolygonHit);
    _polygonHitNotifier.dispose();
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
      _samplesPerReferencePoint =
          stats['samplesPerReferencePoint'] as Map<String, int>? ?? {};
    });
  }

  /// بارگذاری و parse مستقیم GeoJSON (بدون وابستگی به پکیج اضافه)
  Future<void> _loadGeoJson() async {
    try {
      final geoJsonString = await rootBundle
          .loadString('assets/indoor_maps/indoor_level_$_selectedLevel.geojson');
      final data = jsonDecode(geoJsonString) as Map<String, dynamic>;
      final features = data['features'] as List;

      final rooms = <_RoomFeature>[];
      for (final feat in features) {
        final props = feat['properties'] as Map<String, dynamic>?;
        final geom = feat['geometry'] as Map<String, dynamic>?;
        if (geom == null) continue;
        if (geom['type'] != 'Polygon') continue;

        final indoor =
            (props?['indoor'] as String?)?.toLowerCase() ?? 'room';
        final name = props?['name'] as String?;
        final ref = props?['ref'] as String?;

        final coords = geom['coordinates'] as List;
        if (coords.isEmpty) continue;
        // حلقه بیرونی پلیگان
        final outerRing = coords[0] as List;
        final points = <LatLng>[];
        for (final c in outerRing) {
          final lng = (c[0] as num).toDouble();
          final lat = (c[1] as num).toDouble();
          points.add(LatLng(lat, lng));
        }
        if (points.length < 3) continue;

        rooms.add(_RoomFeature(
          name: name,
          ref: ref,
          indoor: indoor,
          points: points,
        ));
      }

      setState(() {
        _roomFeatures = rooms;
        _roomsOnly = rooms
            .where((r) =>
                r.indoor == 'room' &&
                (r.roomValue.isNotEmpty || (r.name ?? '').isNotEmpty))
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading GeoJSON: $e');
    }
  }

  /// وقتی روی یک پلیگان اتاق tap می‌شود، فیلدهای فرم پر می‌شوند
  void _onPolygonHit() {
    final result = _polygonHitNotifier.value;
    if (result == null || result.hitValues.isEmpty) return;
    final room = result.hitValues.first;
    _mapController.move(result.coordinate, _mapController.camera.zoom);
    _selectRoom(room, result.coordinate);
  }

  String _guessBuilding(String? ref) {
    if (ref == null) return '';
    final m = RegExp(r'^([A-Za-z]+)').firstMatch(ref.trim());
    return m?.group(1) ?? '';
  }

  Marker _buildSelectedMarker(LatLng p) {
    return Marker(
      point: p,
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
  }

  void _showFeedback(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.blue.shade700),
    );
  }

  /// تغییر طبقه
  void _changeLevel(int level) {
    setState(() {
      _selectedLevel = level;
      _floorController.text = level.toString();
    });
    _loadGeoJson();
  }

  /// اسکن WiFi و BTS
  Future<void> _scanWifiAndBts() async {
    setState(() => _isScanning = true);

    try {
      final wifiResult = await _scanWifi();
      final cellResult = await _scanBts();
      final gpsResult = await _scanGps();

      setState(() {
        _wifiScanResult = wifiResult;
        _cellScanResult = cellResult;
        _gpsPosition = gpsResult;
      });
    } catch (e) {
      debugPrint('Error scanning: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در اسکن: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<WifiScanResult> _scanWifi() async {
    return await WifiScanner.performScan();
  }

  Future<CellScanResult> _scanBts() async {
    return await CellScanner.performScan();
  }

  Future<Position> _scanGps() async {
    final hasPermission = await Permission.location.isGranted;
    if (!hasPermission) {
      await Permission.location.request();
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// ذخیره Ground Truth
  Future<void> _saveGroundTruth() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لطفاً یک نقطه روی نقشه انتخاب کنید'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    if (_buildingController.text.isEmpty ||
        _floorController.text.isEmpty ||
        _roomController.text.isEmpty ||
        _referencePointIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لطفاً تمام فیلدها را پر کنید'),
            backgroundColor: Colors.orange),
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
        const SnackBar(
            content: Text('✓ Ground Truth ذخیره شد'),
            backgroundColor: Colors.green),
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
        const SnackBar(
            content: Text('لطفاً یک نقطه روی نقشه انتخاب کنید'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    if (_wifiScanResult == null || _cellScanResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لطفاً ابتدا WiFi و BTS را اسکن کنید'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    if (_buildingController.text.isEmpty ||
        _floorController.text.isEmpty ||
        _roomController.text.isEmpty ||
        _referencePointIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لطفاً تمام فیلدها را پر کنید'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final sampleId = await IndoorCsvManager.getNextSampleId(
          _referencePointIdController.text);

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

  /// انتخاب نقطه روی نقشه (tap روی فضای خالی)
  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // اگر tap روی یک پلیگان اتاق افتاده باشد، hitNotifier آن را هندل می‌کند.
    // اینجا فقط وقتی نقطه داخل هیچ اتاقی نبود، انتخاب آزاد انجام می‌شود.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_polygonHitNotifier.value != null &&
          _polygonHitNotifier.value!.hitValues.isNotEmpty) {
        return; // توسط hitNotifier هندل شد
      }
      setState(() {
        _selectedLocation = point;
        _selectedMarker = _buildSelectedMarker(point);
      });
    });
  }

  /// تولید لیست پلیگان‌ها برای PolygonLayer
  List<Polygon<_RoomFeature>> _buildPolygons() {
    return _roomFeatures.map((room) {
      final isRoom = room.indoor == 'room';
      final hasName = room.displayLabel.isNotEmpty;
      return Polygon<_RoomFeature>(
        points: room.points,
        color: isRoom
            ? Colors.blue.withValues(alpha: 0.25)
            : Colors.grey.withValues(alpha: 0.15),
        borderColor: isRoom ? Colors.blue : Colors.blueGrey,
        borderStrokeWidth: isRoom ? 1.5 : 0.8,
        hitValue: isRoom && hasName ? room : null,
        label: (_showLabels && hasName && isRoom)
            ? room.roomValue
            : null,
        labelPlacement: PolygonLabelPlacement.polylabel,
        labelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0x99000000),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Mapping'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          // نمایش/مخفی کردن نام اتاق‌ها
          IconButton(
            tooltip: 'نمایش/مخفی نام اتاق‌ها',
            icon: Icon(_showLabels ? Icons.label : Icons.label_off),
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),
          // جستجوی سریع اتاق با ref
          IconButton(
            tooltip: 'رفتن به اتاق (بر اساس کد)',
            icon: const Icon(Icons.search),
            onPressed: _searchRoom,
          ),
        ],
      ),
      body: Column(
        children: [
          // نقشه
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    const LatLng(_initialLatitude, _initialLongitude),
                initialZoom: _initialZoom,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.example.wifi_knn_locator',
                ),
                if (_roomFeatures.isNotEmpty)
                  PolygonLayer<_RoomFeature>(
                    polygons: _buildPolygons(),
                    polygonLabels: _showLabels,
                    drawLabelsLast: true,
                    hitNotifier: _polygonHitNotifier,
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
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.check,
                                color: Colors.white, size: 16),
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
                  Text(
                      'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}'),
                  Text(
                      'Lon: ${_selectedLocation!.longitude.toStringAsFixed(6)}'),
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
                  // انتخاب طبقه
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('انتخاب طبقه:',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: _availableLevels.map((level) {
                              return ElevatedButton(
                                onPressed: () => _changeLevel(level),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _selectedLevel == level
                                      ? Colors.blue
                                      : Colors.grey,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text('طبقه $level'),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'راهنما: روی کلاس/اتاق tap کنید تا نام و کد آن به‌صورت خودکار پر شود.',
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                          readOnly: true,
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
                          onPressed:
                              _isScanning ? null : _scanWifiAndBts,
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
                          Text('آمار:',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('تعداد Reference Point: $_totalReferencePoints'),
                          Text('تعداد کل نمونه‌ها: $_totalSamples'),
                          const SizedBox(height: 8),
                          if (_samplesPerReferencePoint.isNotEmpty)
                            ..._samplesPerReferencePoint.entries.map((entry) =>
                                Text('${entry.key}: ${entry.value} نمونه')),
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

  /// دیالوگ جستجوی اتاق با کد (ref) و زوم روی آن
  Future<void> _searchRoom() async {
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('رفتن به اتاق'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'مثلاً BC 110 یا 110',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('برو'),
            ),
          ],
        );
      },
    );
    if (query == null || query.isEmpty) return;
    if (_roomsOnly.isEmpty) {
      _showFeedback('اتاقی در این طبقه یافت نشد');
      return;
    }

    final q = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    _RoomFeature? match;
    for (final r in _roomsOnly) {
      final ref = (r.ref ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (ref.isNotEmpty && (ref == q || ref.contains(q))) {
        match = r;
        break;
      }
    }
    match ??= _roomsOnly.firstWhere(
      (r) => (r.name ?? '').toLowerCase().contains(query.toLowerCase()),
      orElse: () => _roomsOnly.first,
    );

    final center = _polygonCenter(match.points);
    _mapController.move(center, 20.0);
    _selectRoom(match, center);
  }

  /// پر کردن فیلدهای فرم بر اساس یک اتاق انتخاب‌شده (دستی یا با tap)
  void _selectRoom(_RoomFeature room, LatLng location) {
    setState(() {
      _selectedLocation = location;
      _selectedMarker = _buildSelectedMarker(location);
      if (room.roomValue.isNotEmpty) {
        _roomController.text = room.roomValue;
      }
      if (_buildingController.text.trim().isEmpty) {
        _buildingController.text = _guessBuilding(room.ref);
      }
      final base = room.roomValue.isNotEmpty
          ? room.roomValue
          : 'level$_selectedLevel';
      _referencePointIdController.text = '${base}_F$_selectedLevel';
    });
    _showFeedback(
        'اتاق انتخاب شد: ${room.displayLabel.isEmpty ? "(بدون نام)" : room.displayLabel}');
  }

  /// مرکز تقریبی یک پلیگان (میانگین رئوس)
  LatLng _polygonCenter(List<LatLng> pts) {
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }
}
