import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data_model.dart';
import 'utils/privacy_utils.dart';

/// ماژول اسکن دکل‌های مخابراتی (Cell Towers)
/// 
/// این ماژول اطلاعات دکل‌های متصل و همسایه را از Android TelephonyManager استخراج می‌کند
/// بدون نیاز به GPS - فقط بر اساس سیگنال‌های رادیویی
class CellScanner {
  static const MethodChannel _channel = MethodChannel('wifi_knn_locator/cell_info');

  /// درخواست مجوزهای لازم برای دسترسی به اطلاعات تلفن
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // برای Android 12+ (API 31+), READ_PHONE_STATE نیاز است
      final phoneStatus = await Permission.phone.request();
      if (!phoneStatus.isGranted) {
        debugPrint('Phone permission denied');
        return false;
      }
    }
    return true;
  }

  /// بررسی وضعیت مجوزها
  static Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      final phoneStatus = await Permission.phone.status;
      return phoneStatus.isGranted;
    }
    return false; // فقط Android پشتیبانی می‌شود
  }

  /// اجرای اسکن دکل‌های مخابراتی
  /// 
  /// این متد:
  /// 1. مجوزها را بررسی می‌کند
  /// 2. اطلاعات دکل متصل (Serving Cell) را دریافت می‌کند
  /// 3. اطلاعات دکل‌های همسایه (Neighboring Cells) را دریافت می‌کند
  /// 4. CellScanResult را برمی‌گرداند
  static Future<CellScanResult> performScan() async {
    // بررسی مجوزها
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('Phone permission not granted for cell scanning');
        // بازگرداندن نتیجه خالی
        final deviceId = await PrivacyUtils.getDeviceId();
        return CellScanResult(
          deviceId: deviceId,
          timestamp: DateTime.now(),
          neighboringCells: [],
        );
      }
    }

    // دریافت شناسه دستگاه
    final deviceId = await PrivacyUtils.getDeviceId();

    // فقط Android پشتیبانی می‌شود
    if (!Platform.isAndroid) {
      debugPrint('Cell scanning is only supported on Android');
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        neighboringCells: [],
      );
    }

    try {
      // فراخوانی متد native برای دریافت اطلاعات دکل‌ها
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCellInfo');
      
      if (result == null) {
        debugPrint('No cell info returned from native code');
        return CellScanResult(
          deviceId: deviceId,
          timestamp: DateTime.now(),
          neighboringCells: [],
        );
      }

      // پارس کردن دکل متصل
      CellTowerInfo? servingCell;
      if (result['serving_cell'] != null) {
        servingCell = _parseCellInfo(result['serving_cell'] as Map<dynamic, dynamic>);
      }

      // پارس کردن دکل‌های همسایه
      final neighboringCells = <CellTowerInfo>[];
      if (result['neighboring_cells'] != null) {
        final neighbors = result['neighboring_cells'] as List<dynamic>;
        for (final neighbor in neighbors) {
          final cellInfo = _parseCellInfo(neighbor as Map<dynamic, dynamic>);
          if (cellInfo != null) {
            neighboringCells.add(cellInfo);
          }
        }
      }

      debugPrint('Cell scan completed: serving cell=${servingCell != null}, neighbors=${neighboringCells.length}');

      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        servingCell: servingCell,
        neighboringCells: neighboringCells,
      );
    } on PlatformException catch (e) {
      debugPrint('Error scanning cells: ${e.message}');
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        neighboringCells: [],
      );
    } catch (e) {
      debugPrint('Unexpected error in cell scan: $e');
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        neighboringCells: [],
      );
    }
  }

  /// پارس کردن اطلاعات یک دکل از Map
  static CellTowerInfo? _parseCellInfo(Map<dynamic, dynamic> map) {
    try {
      return CellTowerInfo(
        cellId: _parseInt(map['cellId']),
        lac: _parseInt(map['lac']),
        tac: _parseInt(map['tac']),
        mcc: _parseInt(map['mcc']),
        mnc: _parseInt(map['mnc']),
        signalStrength: _parseInt(map['signalStrength']),
        networkType: map['networkType'] as String?,
        psc: _parseInt(map['psc']),
        pci: _parseInt(map['pci']),
      );
    } catch (e) {
      debugPrint('Error parsing cell info: $e');
      return null;
    }
  }

  /// تبدیل مقدار به int (با مدیریت null و String)
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    if (value is double) return value.toInt();
    return null;
  }

  /// بررسی اینکه آیا اسکن دکل در دسترس است
  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    return await checkPermissions();
  }

  /// اسکن شبیه‌سازی شده (برای تست)
  static Future<CellScanResult> performSimulatedScan() async {
    final deviceId = await PrivacyUtils.getDeviceId();
    
    final servingCell = CellTowerInfo(
      cellId: 12345,
      lac: 100,
      mcc: 432,
      mnc: 11,
      signalStrength: -75,
      networkType: 'LTE',
      pci: 150,
    );

    final neighboringCells = [
      CellTowerInfo(
        cellId: 12346,
        lac: 100,
        mcc: 432,
        mnc: 11,
        signalStrength: -85,
        networkType: 'LTE',
        pci: 151,
      ),
      CellTowerInfo(
        cellId: 12347,
        tac: 200,
        mcc: 432,
        mnc: 11,
        signalStrength: -90,
        networkType: 'LTE',
        pci: 152,
      ),
    ];

    return CellScanResult(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      servingCell: servingCell,
      neighboringCells: neighboringCells,
    );
  }
}


