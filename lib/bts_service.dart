import 'dart:math';
import 'package:latlong2/latlong.dart';

import 'cell_scanner.dart';
import 'database_helper.dart';

/// سرویس موقعیت‌یابی مبتنی بر BTS
class BTSService {
  /// اسکن دکل و ذخیره تاریخچه
  static Future<CellScanResult> scanAndLog() async {
    final res = await CellScanner.performScan();
    await DatabaseHelper.insert('bts_history', {
      'timestamp': res.timestamp.toIso8601String(),
      'cell_id': res.servingCell?.cellId,
      'lac': res.servingCell?.lac,
      'signal_strength': res.servingCell?.signalStrength,
      'latitude': null,
      'longitude': null,
    });
    return res;
  }

  /// تخمین اولیه موقعیت: اگر بیش از ۲ دکل وجود داشته باشد، از مثلث‌سازی استفاده می‌کنیم
  static LatLng? estimatePosition(CellScanResult scan) {
    final towers = <CellTowerInfo>[];
    if (scan.servingCell != null) towers.add(scan.servingCell!);
    towers.addAll(scan.neighboringCells);

    if (towers.length < 2) return null;

    // ساده‌شده: وزن‌دار centroid براساس قدرت سیگنال
    double sumLat = 0, sumLon = 0, sumW = 0;
    for (final t in towers) {
      final w = 1 / ((t.signalStrength ?? -120).abs() + 1);
      // برای نمونه‌سازی فقط فرض می‌کنیم مختصاتی برای دکل‌ها داریم
      // در عمل باید با سرویس خارجی موقعیت دکل را تعیین کرد.
      final lat = 0.0;
      final lon = 0.0;
      sumLat += lat * w;
      sumLon += lon * w;
      sumW += w;
    }
    if (sumW == 0) return null;
    return LatLng(sumLat / sumW, sumLon / sumW);
  }
}
