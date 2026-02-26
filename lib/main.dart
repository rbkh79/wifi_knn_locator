import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'database_helper.dart';
import 'gps_service.dart';
import 'wifi_service.dart';
import 'bts_service.dart';
import 'hybrid_fusion_service.dart';
import 'map_screen.dart';
import 'error_analysis_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.database;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سامانه موقعیت‌یابی',
      localizationsDelegates: const [],
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng? _gps;
  LatLng? _bts;
  LatLng? _wifi;
  LatLng? _hybrid;

  bool _gpsActive = false;

  String _environment = 'داخلی';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سامانه موقعیت‌یابی')),
        body: Column(
          children: [
            _buildEnvironmentSelector(),
            _buildButtons(),
            Expanded(
                child: MapScreen(
              gpsPosition: _gps,
              btsPosition: _bts,
              wifiPosition: _wifi,
              hybridPosition: _hybrid,
            )),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ErrorAnalysisWidget(
                gps: _gps,
                bts: _bts,
                wifi: _wifi,
                hybrid: _hybrid,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _envButton('داخلی'),
        _envButton('خارجی'),
      ],
    );
  }

  Widget _envButton(String label) {
    final selected = _environment == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ElevatedButton(
        style:
            ElevatedButton.styleFrom(primary: selected ? Colors.blue : null),
        onPressed: () {
          setState(() {
            _environment = label;
          });
        },
        child: Text(label),
      ),
    );
  }

  Widget _buildButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ElevatedButton(
            onPressed: _activateGps, child: const Text('فعال‌سازی GPS')),
        ElevatedButton(onPressed: _scanWifi, child: const Text('اسکن وای‌فای')),
        ElevatedButton(onPressed: _trainMode, child: const Text('حالت آموزش')),
        ElevatedButton(onPressed: _computePosition, child: const Text('محاسبه موقعیت')),
        ElevatedButton(onPressed: _clearData, child: const Text('حذف کامل داده‌های ذخیره‌شده')),
      ],
    );
  }

  Future<void> _activateGps() async {
    final pos = await GPSService.activateGps();
    if (pos != null) {
      setState(() {
        _gps = LatLng(pos.latitude, pos.longitude);
        _gpsActive = true;
      });
    }
  }

  Future<void> _scanWifi() async {
    final result = await WifiService.liveScan();
    showModalBottomSheet(
      context: context,
      builder: (_) => _wifiBottomSheet(result),
    );
  }

  Widget _wifiBottomSheet(WifiScanResult res) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('شبکه‌های وای‌فای شناسایی‌شده', style: Theme.of(context).textTheme.headline6),
            Text('تعداد شبکه‌های کشف‌شده: ${res.accessPoints.length}'),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                  itemCount: res.accessPoints.length,
                  itemBuilder: (c, i) {
                    final ap = res.accessPoints[i];
                    Color color;
                    if (ap.rssi > -50) color = Colors.green;
                    else if (ap.rssi > -70) color = Colors.orange;
                    else color = Colors.red;
                    return ListTile(
                      leading: Icon(Icons.wifi, color: color),
                      title: Text(ap.ssid ?? ap.bssid),
                      subtitle: Text('RSSI: ${ap.rssi}   BSSID: ${_mask(ap.bssid)}   freq: ${ap.frequency ?? '-'}'),
                    );
                  }),
            ),
          ],
        ),
      ),
    );
  }

  String _mask(String bssid) {
    if (bssid.length < 4) return bssid;
    return '${bssid.substring(0, 4)}••••';
  }

  Future<void> _trainMode() async {
    final latlng = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('انتخاب نقطه برای آموزش')),
          body: GestureDetector(
            onTapDown: (details) async {
              // در نسخه ساده فرض می‌کنیم کاربر روی نقطه‌ای در نقشه تپ کرده
              Navigator.of(context).pop(LatLng(0, 0));
            },
            child: const Center(child: Text('نقشه اینجا قرار می‌گیرد')),
          ),
        ),
      ),
    );
    if (latlng != null) {
      final scan = await WifiService.liveScan();
      await WifiService.trainFingerprint(location: latlng, readings: scan.accessPoints);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اثر انگشت ثبت شد')));
    }
  }

  Future<void> _computePosition() async {
    final wifiScan = await WifiService.liveScan();
    final btsScan = await BTSService.scanAndLog();
    final wifiEst =
        await WifiService.estimatePosition(wifiScan.accessPoints.map((e) => e.rssi).toList());
    final btsEst = BTSService.estimatePosition(btsScan);
    final hybridEst = HybridFusionService.fuse(wifi: wifiEst, bts: btsEst);
    setState(() {
      _wifi = wifiEst;
      _bts = btsEst;
      _hybrid = hybridEst;
    });
    await DatabaseHelper.insert('hybrid_estimation_log', {
      'timestamp': DateTime.now().toIso8601String(),
      'wifi_lat': wifiEst?.latitude,
      'wifi_lon': wifiEst?.longitude,
      'bts_lat': btsEst?.latitude,
      'bts_lon': btsEst?.longitude,
      'hybrid_lat': hybridEst?.latitude,
      'hybrid_lon': hybridEst?.longitude,
    });
    if (_gpsActive && _gps != null) {
      final dist = Distance();
      await DatabaseHelper.insert('comparison_log', {
        'timestamp': DateTime.now().toIso8601String(),
        'gps_lat': _gps!.latitude,
        'gps_lon': _gps!.longitude,
        'bts_error': btsEst == null ? null : dist.as(LengthUnit.Meter, _gps!, btsEst),
        'wifi_error': wifiEst == null ? null : dist.as(LengthUnit.Meter, _gps!, wifiEst),
        'hybrid_error': hybridEst == null ? null : dist.as(LengthUnit.Meter, _gps!, hybridEst),
      });
    }
  }

  Future<void> _clearData() async {
    final db = await DatabaseHelper.database;
    await db.delete('gps_history');
    await db.delete('wifi_fingerprint_table');
    await db.delete('bts_history');
    await db.delete('hybrid_estimation_log');
    await db.delete('comparison_log');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('داده‌ها پاک شدند')));
  }
}
