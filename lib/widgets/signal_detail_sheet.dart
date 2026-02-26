import 'package:flutter/material.dart';
import '../data_model.dart';

/// پنل جزئیات سیگنال‌های WiFi و دکل‌ها
class SignalDetailSheet extends StatelessWidget {
  final WifiScanResult? wifiScan;
  final CellScanResult? cellScan;

  const SignalDetailSheet({
    Key? key,
    this.wifiScan,
    this.cellScan,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final wifiList = wifiScan?.accessPoints ?? const [];
    final allCells = <CellTowerInfo>[];
    if (cellScan?.servingCell != null) {
      allCells.add(cellScan!.servingCell!);
    }
    if (cellScan != null) {
      allCells.addAll(cellScan!.neighboringCells);
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      '📶 وای‌فای‌های شناسایی شده (${wifiList.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (wifiList.isEmpty)
                      Text(
                        'هیچ شبکه WiFi یافت نشد',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      ...wifiList.map((ap) {
                        final strengthLabel = _barsForRssi(ap.rssi);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(ap.ssid ?? ap.bssid),
                          subtitle: Text(ap.bssid),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                strengthLabel,
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              Text(
                                '${ap.rssi} dBm',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    Text(
                      '📡 دکل‌های مخابراتی (${allCells.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (allCells.isEmpty)
                      Text(
                        'هیچ دکل فعالی شناسایی نشد',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      ...allCells.map((c) {
                        final strength = c.signalStrength ?? 0;
                        final strengthLabel = _barsForRssi(strength);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.cell_tower),
                          title: Text('${c.networkType ?? '-'}'),
                          subtitle: Text(
                            'CID: ${c.cellId ?? '-'} | TAC/LAC: ${c.tac ?? c.lac ?? '-'}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                strengthLabel,
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              Text(
                                '$strength dBm',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _barsForRssi(int rssi) {
    // Map RSSI to bar pattern like [▂▄▆█]
    if (rssi >= -60) return '[▂▄▆█]';
    if (rssi >= -70) return '[▂▄▆_]';
    if (rssi >= -80) return '[▂▄__]';
    if (rssi >= -90) return '[▂___]';
    return '[____]';
  }
}

