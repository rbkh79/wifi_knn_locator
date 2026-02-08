import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data_model.dart';
import 'utils/privacy_utils.dart';

/// ماژول اسکن دکل‌های مخابراتی (BTS)
///
/// مجوز READ_PHONE_STATE با permission_handler درخواست می‌شود.
/// داده دکل‌های فعال از Android TelephonyManager (MethodChannel) خوانده می‌شود.
/// خروجی: cellId, lac, tac, signalStrength, mcc, mnc
class CellScanner {
  static const MethodChannel _channel = MethodChannel('wifi_knn_locator/cell_info');

  /// درخواست مجوز READ_PHONE_STATE (اندروید)
  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.phone.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('CellScanner: Error requesting phone permission: $e');
      return false;
    }
  }

  /// بررسی وضعیت مجوز
  static Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.phone.status;
    return status.isGranted;
  }

  /// اجرای اسکن دکل‌های مخابراتی
  ///
  /// 1. بررسی/درخواست مجوز READ_PHONE_STATE
  /// 2. فراخوانی native برای getCellInfo
  /// 3. خروجی: CellScanResult با cellId, lac, tac, signalStrength, mcc, mnc
  /// 4. در صورت عدم پشتیبانی دستگاه یا خطا، نتیجه خالی برمی‌گردد (بدون پرتاب خطا)
  static Future<CellScanResult> performScan() async {
    final deviceId = await PrivacyUtils.getDeviceId();

    if (!Platform.isAndroid) {
      debugPrint('CellScanner: Only Android is supported for BTS scanning');
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        neighboringCells: [],
      );
    }

    bool hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('CellScanner: Permission not granted');
        return CellScanResult(
          deviceId: deviceId,
          timestamp: DateTime.now(),
          neighboringCells: [],
        );
      }
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCellInfo');
      if (result == null) {
        debugPrint('CellScanner: Native returned null (device may not support cell info)');
        return CellScanResult(
          deviceId: deviceId,
          timestamp: DateTime.now(),
          neighboringCells: [],
        );
      }

      CellTowerInfo? servingCell;
      if (result['serving_cell'] != null) {
        servingCell = _parseCellInfo(result['serving_cell'] as Map<dynamic, dynamic>);
      }

      final neighboringCells = <CellTowerInfo>[];
      if (result['neighboring_cells'] != null) {
        final list = result['neighboring_cells'] as List<dynamic>;
        for (final item in list) {
          final info = _parseCellInfo(item as Map<dynamic, dynamic>);
          if (info != null) neighboringCells.add(info);
        }
      }

      debugPrint(
        'CellScanner: serving=${servingCell != null}, neighbors=${neighboringCells.length}',
      );
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        servingCell: servingCell,
        neighboringCells: neighboringCells,
      );
    } on PlatformException catch (e) {
      debugPrint('CellScanner: PlatformException ${e.code} - ${e.message}');
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        neighboringCells: [],
      );
    } catch (e) {
      debugPrint('CellScanner: Unexpected error: $e');
      return CellScanResult(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        neighboringCells: [],
      );
    }
  }

  /// پارس یک دکل از Map برگشتی native (کلیدها: cellId, lac, tac, mcc, mnc, signalStrength)
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
      debugPrint('CellScanner: Parse error: $e');
      return null;
    }
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.toInt();
    return null;
  }

  /// آیا اسکن سلولی روی این دستگاه در دسترس است؟
  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    final ok = await checkPermissions();
    if (!ok) return false;
    try {
      final scan = await performScan();
      return scan.allCells.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// اسکن شبیه‌سازی شده برای تست (بدون دستگاه واقعی)
  static Future<CellScanResult> performSimulatedScan() async {
    final deviceId = await PrivacyUtils.getDeviceId();
    final servingCell = CellTowerInfo(
      cellId: 12345,
      lac: 100,
      tac: 200,
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
