import 'package:flutter/material.dart';
// Map rendering simplified to avoid flutter_map API mismatch during build.
// If you want a full map, re-add `flutter_map` with compatible version and update code.
import '../ui/app_theme.dart';
import '../config.dart';
import '../wifi_scanner.dart';
import '../cell_scanner.dart';
import '../services/location_service.dart';
import '../services/unified_localization_service.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../widgets/position_display_panel.dart';
import '../widgets/position_marker.dart';

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
  LocationEstimate? _currentPosition;
  // fallback map center coords (used only for display text)
  final double _mapLat = AppConfig.defaultLatitude;
  final double _mapLng = AppConfig.defaultLongitude;
  
  // Integration: UnifiedLocalizationService for position estimation
  late UnifiedLocalizationService _localizationService;

  @override
  void initState() {
    super.initState();
    // Integration: Initialize UnifiedLocalizationService
    _localizationService = UnifiedLocalizationService(
      LocalDatabase.instance,
    );
  }

  EnvironmentType _mapEnvToWidget() {
    switch (_env) {
      case EnvState.indoor:
        return EnvironmentType.indoor;
      case EnvState.outdoor:
        return EnvironmentType.outdoor;
      case EnvState.hybrid:
        return EnvironmentType.hybrid;
      case EnvState.unknown:
      default:
        return EnvironmentType.unknown;
    }
  }
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
    
    // Integration: Perform unified localization after scans
    try {
      final result = await _localizationService.performLocalization(
        deviceId: 'user-device',
        preferIndoor: _env == EnvState.indoor,
      );
      
      if (result.estimate != null && result.isReliable) {
        setState(() {
          _currentPosition = result.estimate;
        });
      }
    } catch (e) {
      debugPrint('Localization error: $e');
    }
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
                Expanded(
                  child: Text(
                    _envLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_currentPosition != null)
                  Chip(
                    label: Text(
                      '${(_currentPosition!.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: _envColor().withOpacity(0.8),
                    side: const BorderSide(color: Colors.white),
                  ),
              ],
            ),
          ),

          // Map placeholder with position marker overlay
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Container(
                        color: Colors.grey.shade100,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map, size: 56, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text(
                                'نقشه موقتاً در دسترس نیست',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'موقعیت مرکزی: $_mapLat, $_mapLng',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Integration: Position marker overlay
                      if (_currentPosition != null)
                        Center(
                          child: PositionMarker(
                            environmentType: _mapEnvToWidget(),
                            confidence: _currentPosition!.confidence,
                            showConfidenceRing: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Integration: Position display panel
          PositionDisplayPanel(
            estimate: _currentPosition,
            environmentType: _mapEnvToWidget(),
            onRefresh: _startScanAll,
            isLoading: _loading,
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
                            onPressed: _loading ? null : _scanWifi,
                            icon: const Icon(Icons.wifi),
                            label: const Text('اسکن WiFi'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade100,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _scanCell,
                            icon: const Icon(Icons.wifi_tethering),
                            label: const Text('اسکن دکل'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade100,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _startScanAll,
                          icon: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.sync),
                          label: const Text('شروع اسکن'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            minimumSize: const Size(180, 48),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_wifiCount WiFi • $_cellCount دکل',
                      style: const TextStyle(fontSize: 14),
                    ),
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
