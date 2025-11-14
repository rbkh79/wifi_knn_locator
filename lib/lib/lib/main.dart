import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

// Global fingerprint list used by the demo KNN. Declared at top-level so
// helper functions can access it regardless of method ordering inside the
// state class (avoids accidental scope issues during edits).
final List<_Fingerprint> _globalFingerprints = [];

void main() {
  runApp(const MyApp());
}

class KnownAP {
  final String bssid;
  final double lat;
  final double lon;
  KnownAP(this.bssid, this.lat, this.lon);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wi‑Fi KNN Locator',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, KnownAP> db = {};
    // fingerprint dataset: each entry maps bssid->rssi and has lat/lon
    final List<_Fingerprint> fingerprints = [];
  List<WiFiAccessPoint> scanned = [];
  String prediction = 'Not scanned yet';
  bool scanning = false;
    int kValue = 3;

  @override
  void initState() {
    super.initState();
    _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    final csv = await rootBundle.loadString('assets/wifi_db.csv');
    final lines = csv
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'));
    final map = <String, KnownAP>{};
    for (final l in lines) {
      final parts = l.split(',');
      if (parts.length >= 3) {
        final b = parts[0].toLowerCase();
        final lat = double.tryParse(parts[1]) ?? 0.0;
        final lon = double.tryParse(parts[2]) ?? 0.0;
        map[b] = KnownAP(b, lat, lon);
      }
    }
    setState(() => db = map);
      // load fingerprints too
      final fpCsv = await rootBundle.loadString('assets/wifi_fingerprints.csv');
      final fplines = fpCsv
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.startsWith('#'));
      final fps = <_Fingerprint>[];
      for (final l in fplines) {
        final parts = l.split(',');
        if (parts.length >= 3) {
          final lat = double.tryParse(parts[0]) ?? 0.0;
          final lon = double.tryParse(parts[1]) ?? 0.0;
          final mapR = <String, int>{};
          for (var i = 2; i < parts.length; i++) {
            final p = parts[i];
            if (p.contains(':')) {
              final sub = p.split(':');
              if (sub.length >= 2) {
                final b = sub[0].toLowerCase();
                final r = int.tryParse(sub.last) ?? -100;
                mapR[b] = r;
              }
            }
          }
          fps.add(_Fingerprint(lat, lon, mapR));
        }
      }
      // populate the global fingerprint list for use by the KNN predictor
      setState(() {
        _globalFingerprints.clear();
        _globalFingerprints.addAll(fps);
      });
  }

  Future<bool> _requestPermissions() async {
    // For UI preview on web/desktop we skip runtime permission requests
    // and assume permission is granted. On Android you should request
    // location permission before scanning.
    return true;
  }

  Future<void> _scan() async {
    setState(() {
      scanning = true;
      scanned = [];
      prediction = 'Scanning...';
    });

    final ok = await _requestPermissions();
    if (!ok) {
      setState(() {
        scanning = false;
        prediction = 'Location permission denied';
      });
      return;
    }

    // For preview on Windows/web we simulate scanned Wi‑Fi results using
    // entries from the offline database. On Android you should use
    // `wifi_scan` or similar to get real results.
    await Future.delayed(const Duration(milliseconds: 500));
    final list = <WiFiAccessPoint>[];
    var i = 0;
    for (final key in db.keys) {
      if (i >= 6) break;
      list.add(WiFiAccessPoint(ssid: 'AP-$i', bssid: key, level: -30 - i * 8));
      i++;
    }
    setState(() => scanned = list);

    // Use fingerprint-based KNN on simulated scan
    final knnPred = _knnPredictFromFingerprint(list, k: kValue);
    setState(() {
      prediction = knnPred != null
          ? '${knnPred.latitude.toStringAsFixed(6)}, ${knnPred.longitude.toStringAsFixed(6)}'
          : 'No matching APs in dataset';
      scanning = false;
    });

    final pred = _predictFromScan(list, k: 3);
    setState(() {
      prediction = pred != null
          ? '${pred.latitude.toStringAsFixed(6)}, ${pred.longitude.toStringAsFixed(6)}'
          : 'No matching APs in database';
      scanning = false;
    });
  }

  /// Very simple KNN-like estimator:
  /// - find scanned APs present in the offline `db` (bssid -> lat/lon)
  /// - pick top `k` by RSSI and compute a weighted average of their coordinates
  ///   using a simple positive weight derived from RSSI.
  LatLng? _predictFromScan(List<WiFiAccessPoint> list, {int k = 3}) {
    final matches = <_Match>[];
    for (final ap in list) {
      final key = ap.bssid.toLowerCase();
      final known = db[key];
      if (known != null) {
        matches.add(_Match(known.lat, known.lon, ap.level));
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.rssi.compareTo(a.rssi));
    final chosen = matches.take(k).toList();
    double wsum = 0.0, latSum = 0.0, lonSum = 0.0;
    for (final m in chosen) {
      double weight = (m.rssi + 100).toDouble();
      if (weight <= 0) weight = 1.0;
      latSum += m.lat * weight;
      lonSum += m.lon * weight;
      wsum += weight;
    }
    return LatLng(latSum / wsum, lonSum / wsum);
  }

  Future<void> _openInMaps() async {
    if (prediction.startsWith('No') || prediction.startsWith('Scan') || prediction.startsWith('Not')) return;
    final parts = prediction.split(',');
    if (parts.length < 2) return;
    final lat = parts[0].trim();
    final lon = parts[1].trim();
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wi‑Fi KNN Locator')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: scanning ? null : _scan,
                  child: Text(scanning ? 'Scanning...' : 'Scan Wi‑Fi'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _openInMaps,
                  child: const Text('Open in Maps'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Predicted lat,lon:', style: Theme.of(context).textTheme.titleMedium),
            Text(prediction, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Scanned networks:'),
            Expanded(
              child: ListView.builder(
                itemCount: scanned.length,
                itemBuilder: (context, i) {
                  final s = scanned[i];
                  return ListTile(
                    title: Text(s.ssid.isEmpty ? '<hidden>' : s.ssid),
                    subtitle: Text('${s.bssid} • RSSI: ${s.level}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

  /// KNN using fingerprint vectors.
  ///
  /// - `fingerprints` is a list of known locations each containing a map of
  ///   BSSID -> RSSI (training data)
  /// - `list` is the observed scan: BSSID -> RSSI
  /// - We compute a distance between observed vector and each fingerprint
  ///   using squared differences for BSSIDs present in either vector. Missing
  ///   BSSIDs are treated as -100 dBm (very weak).
  /// - We pick the k nearest fingerprints (smallest distance) and do a
  ///   weighted average of their coordinates where weight = 1/(distance+eps).
  ll.LatLng? _knnPredictFromFingerprint(List<WiFiAccessPoint> list, {int k = 3}) {
    if (_globalFingerprints.isEmpty) return null;
    final obs = <String, int>{};
    for (final ap in list) {
      obs[ap.bssid.toLowerCase()] = ap.level;
    }
    final results = <_FpDist>[];
    for (final fp in _globalFingerprints) {
      double dist = 0.0;
      final allKeys = {...fp.rssi.keys, ...obs.keys};
      for (final key in allKeys) {
        final a = obs.containsKey(key) ? obs[key]!.toDouble() : -100.0;
        final b = fp.rssi.containsKey(key) ? fp.rssi[key]!.toDouble() : -100.0;
        final d = a - b;
        dist += d * d;
      }
      results.add(_FpDist(fp, dist));
    }
    results.sort((a, b) => a.dist.compareTo(b.dist));
    final chosen = results.take(k).toList();
    double wsum = 0.0, latSum = 0.0, lonSum = 0.0;
    for (final c in chosen) {
      final w = 1.0 / (c.dist + 1.0); // avoid division by zero
      latSum += c.fp.lat * w;
      lonSum += c.fp.lon * w;
      wsum += w;
    }
    if (wsum == 0) return null;
    return ll.LatLng(latSum / wsum, lonSum / wsum);
  }

class WiFiAccessPoint {
  final String ssid;
  final String bssid;
  final int level;
  WiFiAccessPoint({required this.ssid, required this.bssid, required this.level});
}

class _Match {
  final double lat;
  final double lon;
  final int rssi;
  _Match(this.lat, this.lon, this.rssi);
}

class LatLng {
  final double latitude;
  final double longitude;
  LatLng(this.latitude, this.longitude);
}

class _Fingerprint {
  final double lat;
  final double lon;
  final Map<String, int> rssi;
  _Fingerprint(this.lat, this.lon, this.rssi);
}

class _FpDist {
  final _Fingerprint fp;
  final double dist;
  _FpDist(this.fp, this.dist);
}
