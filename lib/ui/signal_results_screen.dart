import 'package:flutter/material.dart';
import '../wifi_scanner.dart';
import '../cell_scanner.dart';
import '../data_model.dart';
import '../ui/app_theme.dart';
import '../utils/permission_utils.dart';

class SignalResultsScreen extends StatefulWidget {
  const SignalResultsScreen({Key? key}) : super(key: key);

  @override
  State<SignalResultsScreen> createState() => _SignalResultsScreenState();
}

class _SignalResultsScreenState extends State<SignalResultsScreen> with TickerProviderStateMixin {
  TabController? _tabController;
  WifiScanResult? _wifiResult;
  CellScanResult? _cellResult;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      final w = await WifiScanner.performScan();
      CellScanResult? c;
      try {
        c = await CellScanner.performScan();
      } catch (_) {}
      setState(() {
        _wifiResult = w;
        _cellResult = c;
      });
    } catch (e) {
      debugPrint('Refresh scan error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildCellTab() {
    if (_cellResult == null || (_cellResult!.servingCell == null && _cellResult!.neighboringCells.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اطلاعات دکل موجود نیست'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final granted = await PermissionUtils.requestLocationAndPhonePermissions();
                  if (!granted) {
                    await PermissionUtils.openAppSettingsIfNeeded(context);
                    return;
                  }
                  await _refreshAll();
                },
                child: const Text('درخواست مجوز / اسکن مجدد'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
              )
            ],
          ),
        ),
      );
    }

    final List<CellTowerInfo> all = [];
    if (_cellResult!.servingCell != null) all.add(_cellResult!.servingCell!);
    all.addAll(_cellResult!.neighboringCells);

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: all.length,
      itemBuilder: (context, i) {
        final c = all[i];
        final operatorName = c.operatorName ?? 'ناشناس';
        Color opColor = Colors.grey;
        if (operatorName.contains('MCI') || operatorName.contains('Hamrah')) opColor = Colors.blue;
        if (operatorName.contains('Irancell') || operatorName.contains('MTN')) opColor = Colors.orange;
        if (operatorName.contains('RighTel')) opColor = Colors.green;

        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: opColor, child: const Icon(Icons.sim_card, color: Colors.white)),
            title: Text(operatorName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cell ID: ${c.cellId ?? '-'}   TAC/LAC: ${c.tac ?? c.lac ?? '-'}'),
                Text('Network: ${c.networkType ?? '-'}'),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${c.signalStrength ?? 0} dBm', style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWifiTab() {
    if (_wifiResult == null || _wifiResult!.accessPoints.isEmpty) {
      return Center(child: Text(_loading ? 'در حال اسکن...' : 'هیچ شبکه WiFi یافت نشد'));
    }
    final aps = _wifiResult!.accessPoints;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: aps.length,
      itemBuilder: (context, i) {
        final a = aps[i];
        return Card(
          child: ListTile(
            title: Text(a.ssid ?? a.bssid ?? 'نامشخص'),
            subtitle: Text(a.bssid),
            trailing: Text('${a.rssi} dBm', style: const TextStyle(fontFamily: 'monospace')),
          ),
        );
      },
    );
  }

  Widget _buildCombinedTab() {
    return Center(child: Text('نمایش ترکیبی (Hybrid) - در دست توسعه'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نتایج سیگنال‌ها'),
        backgroundColor: AppTheme.primary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'WiFi'), Tab(text: 'دکل مخابراتی'), Tab(text: 'ترکیبی')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWifiTab(),
          _buildCellTab(),
          _buildCombinedTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _refreshAll,
        icon: const Icon(Icons.refresh),
        label: const Text('اسکن مجدد'),
        backgroundColor: AppTheme.primary,
      ),
    );
  }
}
