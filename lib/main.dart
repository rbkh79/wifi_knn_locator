import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:csv/csv.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_info_plus/wifi_info_plus.dart';

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
      ),
      home: const HomePage(),
      localizationsDelegates: const [],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _result = 'فشار دکمه اسکن را بزن';
  bool _loading = false;
  List<Map<String, dynamic>> _fingerprints = [];

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
      setState(() => _result = 'خطا در بارگذاری دادگان: $e');
    }
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _result = 'در حال اسکن...';
    });
    try {
      // Request permissions
      if (Platform.isAndroid) {
        final locationStatus = await Permission.location.request();
        if (!locationStatus.isGranted) {
          setState(() => _result = 'دسترسی مکان رد شد');
          return;
        }
      }

      // Get observed WiFi networks
      final observed = await _scanRealWiFi();

      if (observed.isEmpty) {
        setState(() => _result = 'هیچ شبکهٔ وای‌فایی یافت نشد. دستگاه را دوباره سعی کن.');
        return;
      }

      // Perform KNN prediction
      final prediction = _knnPredictFromFingerprint(observed, k: 3);
      
      // Display found networks
      final networkList = observed.map((ap) => '${ap.bssid}: ${ap.rssi} dBm').join('\n');
      
      setState(() {
        _result =
            'شبکه‌های یافت شده:\n$networkList\n\n'
            'موقعیت برآورد شده:\n'
            'Latitude: ${prediction['lat'].toStringAsFixed(6)}\n'
            'Longitude: ${prediction['lon'].toStringAsFixed(6)}\n'
            '(KNN k=3)';
      });
    } catch (e) {
      setState(() => _result = 'خطا: $e');
      debugPrint('Scan error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<List<WiFiAccessPoint>> _scanRealWiFi() async {
    try {
      // Request WIFI state permission
      if (Platform.isAndroid) {
        final wifiStatus = await Permission.location.request();
        if (!wifiStatus.isGranted) {
          throw Exception('Location permission not granted');
        }
      }

      // Get list of available WiFi networks
      final result = await WiFiScan.instance.getScannedNetworks(
        shouldOpenLocationSettings: true,
      );

      debugPrint('WiFi scan result: $result');

      // Convert to WiFiAccessPoint list
      final accessPoints = result
          .map((network) => WiFiAccessPoint(
                bssid: network.bssid ?? '',
                rssi: network.level ?? -100,
              ))
          .where((ap) => ap.bssid.isNotEmpty)
          .toList();

      // Sort by signal strength (strongest first)
      accessPoints.sort((a, b) => b.rssi.compareTo(a.rssi));

      debugPrint('Found ${accessPoints.length} WiFi networks');
      for (final ap in accessPoints) {
        debugPrint('BSSID: ${ap.bssid}, RSSI: ${ap.rssi}');
      }

      return accessPoints;
    } catch (e) {
      debugPrint('WiFi scan error: $e');
      // Fallback: return simulated data if real scan fails
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

  Future<void> _openInMaps(double lat, double lon) async {
    final url = 'geo:$lat,$lon?q=$lat,$lon';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi KNN Locator'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                _result,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _loading ? null : _scan,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('شروع اسکن'),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  final parts = _result.split('\n');
                  if (parts.length >= 3) {
                    final latStr = parts[1]
                        .replaceAll('Latitude: ', '')
                        .trim();
                    final lonStr = parts[2]
                        .replaceAll('Longitude: ', '')
                        .replaceAll(RegExp(r'\(.*'), '')
                        .trim();

                    final lat = double.tryParse(latStr) ?? 0.0;
                    final lon = double.tryParse(lonStr) ?? 0.0;

                    if (lat != 0.0 && lon != 0.0) {
                      _openInMaps(lat, lon);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ابتدا اسکن را اجرا کن')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.map),
                label: const Text('نقشه'),
              ),
            ],
          ),
        ),
      ),
    );
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
