import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:csv/csv.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
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
      localizationsDelegates: const [],
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
  bool _loading = false;
  List<Map<String, dynamic>> _fingerprints = [];
  List<WiFiAccessPoint> _scannedNetworks = [];
  Map<String, double>? _prediction;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    try {
      final csvData = await DefaultAssetBundle.of(context)
          .loadString('assets/wifi_fingerprints.csv');
      final rows = const CsvToListConverter().convert(csvData);
      _fingerprints = [];
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].isEmpty) continue;
        final lat = double.tryParse(rows[i][0].toString()) ?? 0.0;
        final lon = double.tryParse(rows[i][1].toString()) ?? 0.0;
        final Map<String, dynamic> fp = {'lat': lat, 'lon': lon};
        for (int j = 2; j < rows[i].length; j += 2) {
          if (j + 1 < rows[i].length) {
            final bssid = rows[i][j].toString();
            final rssi = int.tryParse(rows[i][j + 1].toString()) ?? -100;
            fp[bssid] = rssi;
          }
        }
        _fingerprints.add(fp);
      }
      debugPrint('Loaded ${_fingerprints.length} fingerprints');
    } catch (e) {
      debugPrint('Error loading fingerprints: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری دادگان: $e')),
        );
      }
    }
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _scannedNetworks = [];
      _prediction = null;
    });

    try {
      // Request permissions
      if (Platform.isAndroid) {
        final locationStatus = await Permission.location.request();
        if (!locationStatus.isGranted) {
          setState(() => _loading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('دسترسی مکان رد شد. لطفاً مجوز را در تنظیمات فعال کنید.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Get observed WiFi networks
      final observed = await _scanRealWiFi();

      if (observed.isEmpty) {
        setState(() {
          _loading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هیچ شبکهٔ وای‌فایی یافت نشد. لطفاً WiFi را روشن کنید.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Perform KNN prediction
      final prediction = _knnPredictFromFingerprint(observed, k: 3);

      setState(() {
        _scannedNetworks = observed;
        _prediction = prediction;
        _loading = false;
      });

      // Update map to show prediction
      if (prediction['lat'] != 0.0 && prediction['lon'] != 0.0) {
        _mapController.move(
          LatLng(prediction['lat']!, prediction['lon']!),
          16.0,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اسکن با موفقیت انجام شد!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در اسکن: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<WiFiAccessPoint>> _scanRealWiFi() async {
    try {
      // Ensure we have location permission on Android
      if (Platform.isAndroid) {
        final wifiStatus = await Permission.location.request();
        if (!wifiStatus.isGranted) {
          throw Exception('Location permission not granted');
        }
      }

      // Start a scan
      try {
        await WiFiScan.instance.startScan();
      } catch (e) {
        debugPrint('startScan() threw: $e');
      }

      // Wait for scan results
      await Future.delayed(const Duration(seconds: 2));

      List<dynamic>? results;
      try {
        results = await WiFiScan.instance.getScannedResults();
      } catch (e) {
        debugPrint('getScannedResults() not available or failed: $e');
        results = null;
      }

      // Convert to WiFiAccessPoint list
      if (results == null || results.isEmpty) {
        debugPrint('No real scan results, using simulated data');
        return _simulateScan();
      }

      final accessPoints = results
          .map((network) {
            final dyn = network as dynamic;
            final String bssid = (dyn.bssid ?? dyn.bss?.toString() ?? '') as String;
            final int rssi = (dyn.level ?? dyn.rssi ?? -100) as int;
            return WiFiAccessPoint(bssid: bssid, rssi: rssi);
          })
          .where((ap) => ap.bssid.isNotEmpty)
          .cast<WiFiAccessPoint>()
          .toList();

      accessPoints.sort((a, b) => b.rssi.compareTo(a.rssi));
      debugPrint('Found ${accessPoints.length} WiFi networks');
      for (final ap in accessPoints) {
        debugPrint('BSSID: ${ap.bssid}, RSSI: ${ap.rssi}');
      }

      return accessPoints;
    } catch (e) {
      debugPrint('WiFi scan error: $e');
      return _simulateScan();
    }
  }

  List<WiFiAccessPoint> _simulateScan() {
    return [
      WiFiAccessPoint(bssid: '00:1A:2B:3C:4D:5E', rssi: -45),
      WiFiAccessPoint(bssid: '00:1A:2B:3C:4D:5F', rssi: -65),
      WiFiAccessPoint(bssid: '00:1A:2B:3C:4D:60', rssi: -72),
    ];
  }

  Map<String, double> _knnPredictFromFingerprint(
      List<WiFiAccessPoint> observed,
      {int k = 3}) {
    if (_fingerprints.isEmpty) {
      return {'lat': 0.0, 'lon': 0.0};
    }

    // Build observed map
    final observedMap = <String, int>{};
    for (final ap in observed) {
      observedMap[ap.bssid] = ap.rssi;
    }

    // Calculate distances to all fingerprints
    final List<_DistanceRecord> distances = [];
    for (int i = 0; i < _fingerprints.length; i++) {
      final fp = _fingerprints[i];
      double dist = 0.0;

      // Collect all BSSID keys (union of observed and fingerprint)
      final allKeys = <String>{...observedMap.keys};
      for (final key in fp.keys) {
        if (key != 'lat' && key != 'lon') {
          allKeys.add(key);
        }
      }

      // Euclidean distance
      for (final key in allKeys) {
        final obsRssi = observedMap[key]?.toDouble() ?? -100.0;
        final fpRssi = (fp[key] as num?)?.toDouble() ?? -100.0;
        dist += (obsRssi - fpRssi) * (obsRssi - fpRssi);
      }

      distances.add(_DistanceRecord(
        distance: dist,
        index: i,
      ));
    }

    // Sort by distance and get k nearest
    distances.sort((a, b) => a.distance.compareTo(b.distance));

    // Weighted average: weight = 1 / (distance + 1)
    double latSum = 0.0, lonSum = 0.0, weightSum = 0.0;
    final kNearest = k < distances.length ? k : distances.length;
    for (int i = 0; i < kNearest; i++) {
      final idx = distances[i].index;
      final dist = distances[i].distance;
      final weight = 1.0 / (dist + 1.0);

      latSum += (_fingerprints[idx]['lat'] as num).toDouble() * weight;
      lonSum += (_fingerprints[idx]['lon'] as num).toDouble() * weight;
      weightSum += weight;
    }

    return {
      'lat': weightSum > 0 ? latSum / weightSum : 0.0,
      'lon': weightSum > 0 ? lonSum / weightSum : 0.0,
    };
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
  Widget build(BuildContext context) {
    final defaultLocation = LatLng(35.6762, 51.4158); // تهران
    final predictionLocation = _prediction != null &&
            _prediction!['lat'] != 0.0 &&
            _prediction!['lon'] != 0.0
        ? LatLng(_prediction!['lat']!, _prediction!['lon']!)
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
              Container(
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
                child: Row(
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
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _scan,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: Row(
                  children: [
                    // Left Panel - Info
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            // Prediction Card
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.shade600,
                                      Colors.blue.shade800,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.white,
                                          size: 28,
                                        ),
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
                                    if (_prediction != null &&
                                        _prediction!['lat'] != 0.0 &&
                                        _prediction!['lon'] != 0.0) ...[
                                      _buildInfoRow(
                                        'عرض جغرافیایی',
                                        _prediction!['lat']!.toStringAsFixed(6),
                                        Icons.explore,
                                      ),
                                      const SizedBox(height: 8),
                                      _buildInfoRow(
                                        'طول جغرافیایی',
                                        _prediction!['lon']!.toStringAsFixed(6),
                                        Icons.explore,
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openInExternalMaps(
                                            _prediction!['lat']!,
                                            _prediction!['lon']!,
                                          ),
                                          icon: const Icon(Icons.open_in_new),
                                          label: const Text('باز کردن در Google Maps'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.blue.shade800,
                                          ),
                                        ),
                                      ),
                                    ] else
                                      const Text(
                                        'برای مشاهده موقعیت، ابتدا اسکن را انجام دهید',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Networks Card
                            Expanded(
                              child: Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.wifi,
                                            color: Colors.blue.shade700,
                                            size: 24,
                                          ),
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
                                          if (_scannedNetworks.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade100,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${_scannedNetworks.length}',
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
                                        child: _scannedNetworks.isEmpty
                                            ? Center(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.wifi_off,
                                                      size: 64,
                                                      color: Colors.grey.shade300,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      'هنوز اسکنی انجام نشده',
                                                      style: TextStyle(
                                                        color: Colors.grey.shade600,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: _scannedNetworks.length,
                                                itemBuilder: (context, index) {
                                                  final network =
                                                      _scannedNetworks[index];
                                                  return _buildNetworkItem(network);
                                                },
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right Panel - Map
                    Expanded(
                      flex: 2,
                      child: Container(
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
                              initialCenter: predictionLocation,
                              initialZoom: 15.0,
                              minZoom: 5.0,
                              maxZoom: 18.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.wifi_knn_locator',
                              ),
                              if (_prediction != null &&
                                  _prediction!['lat'] != 0.0 &&
                                  _prediction!['lon'] != 0.0)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: predictionLocation,
                                      width: 80,
                                      height: 80,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
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
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
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

  Widget _buildNetworkItem(WiFiAccessPoint network) {
    final signalStrength = _getSignalStrength(network.rssi);
    final signalColor = _getSignalColor(network.rssi);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
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
            child: Icon(
              Icons.wifi,
              color: signalColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network.bssid,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.signal_cellular_alt,
                      size: 16,
                      color: signalColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${network.rssi} dBm',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getSignalStrength(int rssi) {
    if (rssi >= -50) return 'عالی';
    if (rssi >= -60) return 'خوب';
    if (rssi >= -70) return 'متوسط';
    if (rssi >= -80) return 'ضعیف';
    return 'خیلی ضعیف';
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.lightGreen;
    if (rssi >= -70) return Colors.orange;
    if (rssi >= -80) return Colors.deepOrange;
    return Colors.red;
  }
}

class WiFiAccessPoint {
  final String bssid;
  final int rssi;

  WiFiAccessPoint({required this.bssid, required this.rssi});
}

class _DistanceRecord {
  final double distance;
  final int index;

  _DistanceRecord({
    required this.distance,
    required this.index,
  });
}
