import 'dart:math';
import 'package:latlong2/latlong.dart';

import 'cell_scanner.dart';
import 'database_helper.dart';
import 'data_model.dart';

// ensure CellScanResult and CellTowerInfo are visible

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
  /// 
  /// توجه: این متد نیاز به مختصات واقعی دکل‌ها دارد. در حال حاضر null برمی‌گرداند
  /// چون مختصات دکل‌ها در دیتابیس ذخیره نشده‌اند.
  /// برای استفاده واقعی، باید از سرویس‌هایی مثل Mozilla Location Service یا OpenCellID استفاده کنید.
  static LatLng? estimatePosition(CellScanResult scan) {
    // TODO: پیاده‌سازی واقعی با استفاده از سرویس خارجی برای مختصات دکل‌ها
    // برای مثال:
    // 1. Cell ID را به سرویس OpenCellID بفرستید
    // 2. مختصات دکل را دریافت کنید
    // 3. از مثلث‌سازی یا weighted centroid استفاده کنید
    
    // فعلاً null برمی‌گردانیم چون مختصات دکل‌ها نداریم
    return null;
  }
}
