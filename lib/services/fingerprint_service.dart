import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../wifi_scanner.dart';
import '../utils/privacy_utils.dart';

/// سرویس مدیریت اثرانگشت‌ها (Training Mode)
class FingerprintService {
  final LocalDatabase _database;

  FingerprintService(this._database);

  /// ذخیره اثرانگشت جدید (Training Mode)
  /// 
  /// پارامترها:
  /// - latitude, longitude: مختصات نقطه مرجع
  /// - zoneLabel: لیبل ناحیه (اختیاری)
  /// - scanResult: نتیجه اسکن Wi-Fi (اگر null باشد، اسکن جدید انجام می‌شود)
  Future<FingerprintEntry> saveFingerprint({
    required double latitude,
    required double longitude,
    String? zoneLabel,
    WifiScanResult? scanResult,
    String? sessionId,
    String? contextId,
  }) async {
    // اگر اسکن ارائه نشده، یک اسکن جدید انجام می‌دهیم
    if (scanResult == null) {
      scanResult = await WifiScanner.performScan();
    }

    // تولید شناسه یکتا برای اثرانگشت
    final fingerprintId = _generateFingerprintId(latitude, longitude);

    // دریافت شناسه دستگاه
    final deviceId = await PrivacyUtils.getDeviceId();

    // ایجاد ورودی اثرانگشت
    final fingerprint = FingerprintEntry(
      fingerprintId: fingerprintId,
      latitude: latitude,
      longitude: longitude,
      zoneLabel: zoneLabel,
      sessionId: sessionId,
      contextId: contextId,
      accessPoints: scanResult.accessPoints,
      createdAt: DateTime.now(),
      deviceId: deviceId,
    );

    // ذخیره در پایگاه داده
    await _database.insertFingerprint(fingerprint);

    debugPrint('Fingerprint saved: $fingerprintId at ($latitude, $longitude)');

    return fingerprint;
  }

  /// تولید شناسه یکتا برای اثرانگشت
  String _generateFingerprintId(double lat, double lon) {
    // استفاده از مختصات و timestamp برای تولید شناسه یکتا
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'fp_${lat.toStringAsFixed(6)}_${lon.toStringAsFixed(6)}_$timestamp';
  }

  /// دریافت تمام اثرانگشت‌ها
  Future<List<FingerprintEntry>> getAllFingerprints() async {
    return await _database.getAllFingerprints();
  }

  /// حذف اثرانگشت
  Future<bool> deleteFingerprint(String fingerprintId) async {
    try {
      await _database.deleteFingerprint(fingerprintId);
      return true;
    } catch (e) {
      debugPrint('Error deleting fingerprint: $e');
      return false;
    }
  }

  /// تعداد اثرانگشت‌ها
  Future<int> getFingerprintCount() async {
    return await _database.getFingerprintCount();
  }

  /// پاک کردن تمام اثرانگشت‌ها
  Future<void> clearAllFingerprints() async {
    await _database.clearAll();
  }
}


















