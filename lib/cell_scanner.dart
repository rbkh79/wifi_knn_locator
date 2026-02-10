import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data_model.dart';
import 'utils/privacy_utils.dart';
import 'services/location_service.dart';

/// ماژول اسکن دکل‌های مخابراتی (BTS)
///
/// - مجوز Location + READ_PHONE_STATE (در عمل برای Android 10+ مهم‌تر Location است)
/// - داده دکل‌های فعال از Android TelephonyManager (MethodChannel) خوانده می‌شود.
/// - خروجی: cellId, lac, tac, signalStrength, mcc, mnc + نام اپراتور ایرانی
class CellScanner {
  static const MethodChannel _channel =
      MethodChannel('wifi_knn_locator/cell_info');

  /// درخواست مجوزهای لازم برای اسکن سلولی
  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final locStatus = await Permission.location.request();
      final phoneStatus = await Permission.phone.request();
      final granted = locStatus.isGranted && phoneStatus.isGranted;
      if (!granted) {
        debugPrint(
            'CellScanner: Location/Phone permissions not granted for cell scanning');
      }
      return granted;
    } catch (e) {
      debugPrint('CellScanner: Error requesting permissions: $e');
      return false;
    }
  }

  /// بررسی وضعیت مجوزها
  static Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return false;
    final loc = await Permission.location.status;
    final phone = await Permission.phone.status;
    return loc.isGranted && phone.isGranted;
  }

  /// اجرای اسکن دکل‌های مخابراتی
  ///
  /// 1. بررسی/درخواست مجوزهای Location + Phone
  /// 2. بررسی فعال بودن Location Service
  /// 3. فراخوانی native برای getCellInfo
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

    // Android 10+ نیاز به Location Service روشن دارد
    final locEnabled = await LocationService.isLocationServiceEnabled();
    if (!locEnabled) {
      debugPrint(
          'CellScanner: Location service is disabled. Enable it to access cell info.');
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
        return CellScanResult(
          deviceId: deviceId,
          timestamp: DateTime.now(),
          neighboringCells: [],
        );
      }
    }

    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getCellInfo');
      if (result == null) {
        debugPrint(
            'CellScanner: Native returned null (no cell info or no permission)');
        return CellScanResult(
          deviceId: deviceId,
          timestamp: DateTime.now(),
          neighboringCells: [],
        );
      }

      CellTowerInfo? servingCell;
      if (result['serving_cell'] != null) {
        servingCell =
            _parseCellInfo(result['serving_cell'] as Map<dynamic, dynamic>);
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
      final mcc = _parseInt(map['mcc']);
      final mnc = _parseInt(map['mnc']);
      final info = CellTowerInfo(
        cellId: _parseInt(map['cellId']),
        lac: _parseInt(map['lac']),
        tac: _parseInt(map['tac']),
        mcc: mcc,
        mnc: mnc,
        signalStrength: _parseInt(map['signalStrength']),
        networkType: map['networkType'] as String?,
        psc: _parseInt(map['psc']),
        pci: _parseInt(map['pci']),
      );

      final opName = resolveIranOperator(mcc, mnc);
      if (opName != null) {
        debugPrint('CellScanner: operator=$opName, cell=${info.uniqueId}');
      }

      return info;
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
    if (!await LocationService.isLocationServiceEnabled()) return false;
    return await checkPermissions();
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
        mnc: 35,
        signalStrength: -85,
        networkType: 'LTE',
        pci: 151,
      ),
      CellTowerInfo(
        cellId: 12347,
        tac: 200,
        mcc: 432,
        mnc: 20,
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

/// نگاشت MCC/MNC به اپراتورهای ایرانی
String? resolveIranOperator(int? mcc, int? mnc) {
  if (mcc != 432 || mnc == null) return null;
  switch (mnc) {
    case 11:
    case 70:
      return 'MCI (Hamrah Aval)';
    case 35:
      return 'MTN Irancell';
    case 20:
      return 'RighTel';
    case 12:
      return 'HiWEB';
    case 32:
      return 'Taliya';
    default:
      return 'Iran MCC 432 / MNC $mnc';
  }
}

/// اکستِنشن کمکی برای خواندن نام اپراتور
extension CellTowerOperatorExt on CellTowerInfo {
  String? get operatorName => resolveIranOperator(mcc, mnc);
}

