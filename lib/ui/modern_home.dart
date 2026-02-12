import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../ui/app_theme.dart';
import '../config.dart';
import '../wifi_scanner.dart';
import '../cell_scanner.dart';
import '../services/location_service.dart';
import '../data_model.dart';

class ModernHome extends StatefulWidget {
  const ModernHome({Key? key}) : super(key: key);

  @override
  State<ModernHome> createState() => _ModernHomeState();
}

enum EnvState { indoor, outdoor, hybrid, unknown }

class _ModernHomeState extends State<ModernHome> {
  EnvState _env = EnvState.unknown;
  int _wifiCount = 0;
  int _cellCount = 0;
  bool _loading = false;
  WifiScanResult? _lastWifi;
  CellScanResult? _lastCell;
  LatLng _mapCenter = LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude);

  Color _envColor() {
    switch (_env) {
      case EnvState.indoor:
        return const Color(0xFF4285F4);
      case EnvState.outdoor:
        return const Color(0xFF34A853);
      case EnvState.hybrid:
        return const Color(0xFFAA46BB);
      case EnvState.unknown:
      default:
        return Colors.grey;
    }
  }

  String _envLabel() {
    switch (_env) {
      case EnvState.indoor:
        return 'Indoor';
      case EnvState.outdoor:
        return 'Outdoor';
      case EnvState.hybrid:
        return 'Hybrid';
      case EnvState.unknown:
      default:
        return 'Unknown';
    }
  }

  Future<void> _scanWifi() async {
    setState(() => _loading = true);
    try {
      final r = await WifiScanner.performScan();
      setState(() {
        _lastWifi = r;
        _wifiCount = r.accessPoints.length;
        _evaluateEnv();
      });
    } catch (e) {
      debugPrint('WiFi scan error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _scanCell() async {
    setState(() => _loading = true);
    try {
      final r = await CellScanner.performScan();
      setState(() {
        _lastCell = r;
        final count = (r.servingCell != null ? 1 : 0) + r.neighboringCells.length;
        _cellCount = count;
        _evaluateEnv();
      });
    } catch (e) {
      debugPrint('Cell scan error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _startScanAll() async {
    await _scanWifi();
    await _scanCell();
  }

  void _evaluateEnv() {
    final hasWifi = _wifiCount >= 3;
    final hasCell = _cellCount >= 1;
    setState(() {
      if (hasWifi && hasCell) _env = EnvState.hybrid;
      else if (hasWifi) _env = EnvState.indoor;
      else if (hasCell) _env = EnvState.outdoor;
      else _env = EnvState.unknown;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('موقعیت‌یابی هوشمند'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          )
        ],
      ),
      body: Column(
        children: [
          // Environment badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: _envColor(),
            child: Row(
              children: [
                Icon(Icons.place, color: Colors.white),
                const SizedBox(width: 8),
                Text(_envLabel(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // Map
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      center: _mapCenter,
                      zoom: AppConfig.defaultMapZoom,
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      MarkerLayer(markers: [
                        // Current location marker (placeholder)
                        Marker(
                          point: _mapCenter,
                          width: 36,
                          height: 36,
                          builder: (c) => const Icon(Icons.my_location, color: Colors.blue, size: 32),
                        ),
                        // Reference markers (if in training, we could show green ones) - omitted here
                      ])
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Control panel
          Container(
            height: 120,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.transparent,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _scanWifi,
                            icon: const Icon(Icons.wifi),
                            label: const Text('اسکن WiFi'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade100, foregroundColor: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _scanCell,
                            icon: const Icon(Icons.wifi_tethering),
                            label: const Text('اسکن دکل'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100, foregroundColor: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _startScanAll,
                          icon: const Icon(Icons.sync),
                          label: const Text('شروع اسکن'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, minimumSize: const Size(180, 48)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('$_wifiCount WiFi • $_cellCount دکل', style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pushNamed('/signals'),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.signal_cellular_alt),
        tooltip: 'مشاهده نتایج سیگنال‌ها',
      ),
    );
  }
}
