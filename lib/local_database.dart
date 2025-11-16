import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'data_model.dart';
import 'config.dart';

/// مدیریت پایگاه داده محلی (SQLite) برای ذخیره اثرانگشت‌ها
class LocalDatabase {
  static Database? _database;
  static final LocalDatabase instance = LocalDatabase._internal();

  LocalDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// مقداردهی اولیه پایگاه داده
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConfig.databaseName);

    return await openDatabase(
      path,
      version: AppConfig.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// ایجاد جداول در اولین اجرا
  Future<void> _onCreate(Database db, int version) async {
    // جدول اثرانگشت‌ها
    await db.execute('''
      CREATE TABLE fingerprints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint_id TEXT UNIQUE NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        zone_label TEXT,
        created_at TEXT NOT NULL,
        device_id TEXT
      )
    ''');

    // جدول نقاط دسترسی Wi-Fi (برای هر اثرانگشت)
    await db.execute('''
      CREATE TABLE access_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint_id TEXT NOT NULL,
        bssid TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        frequency INTEGER,
        ssid TEXT,
        FOREIGN KEY (fingerprint_id) REFERENCES fingerprints(fingerprint_id) ON DELETE CASCADE
      )
    ''');

    // ایجاد ایندکس‌ها برای بهبود عملکرد
    await db.execute('CREATE INDEX idx_fingerprint_id ON fingerprints(fingerprint_id)');
    await db.execute('CREATE INDEX idx_ap_fingerprint_id ON access_points(fingerprint_id)');
    await db.execute('CREATE INDEX idx_ap_bssid ON access_points(bssid)');
  }

  /// به‌روزرسانی پایگاه داده (در صورت تغییر نسخه)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // در آینده می‌توان منطق به‌روزرسانی را اضافه کرد
    debugPrint('Database upgrade from $oldVersion to $newVersion');
  }

  /// افزودن اثرانگشت جدید
  Future<int> insertFingerprint(FingerprintEntry fingerprint) async {
    final db = await database;
    
    try {
      // شروع تراکنش
      await db.transaction((txn) async {
        // افزودن رکورد اصلی
        final fingerprintId = await txn.insert(
          'fingerprints',
          {
            'fingerprint_id': fingerprint.fingerprintId,
            'latitude': fingerprint.latitude,
            'longitude': fingerprint.longitude,
            'zone_label': fingerprint.zoneLabel,
            'created_at': fingerprint.createdAt.toIso8601String(),
            'device_id': fingerprint.deviceId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // افزودن نقاط دسترسی
        for (final ap in fingerprint.accessPoints) {
          await txn.insert(
            'access_points',
            {
              'fingerprint_id': fingerprint.fingerprintId,
              'bssid': ap.bssid,
              'rssi': ap.rssi,
              'frequency': ap.frequency,
              'ssid': ap.ssid,
            },
          );
        }
      });

      debugPrint('Fingerprint inserted: ${fingerprint.fingerprintId}');
      return 1;
    } catch (e) {
      debugPrint('Error inserting fingerprint: $e');
      rethrow;
    }
  }

  /// دریافت تمام اثرانگشت‌ها
  Future<List<FingerprintEntry>> getAllFingerprints() async {
    final db = await database;
    
    // دریافت رکوردهای اصلی
    final fingerprintMaps = await db.query('fingerprints', orderBy: 'created_at DESC');
    
    final fingerprints = <FingerprintEntry>[];
    
    for (final fpMap in fingerprintMaps) {
      final fingerprintId = fpMap['fingerprint_id'] as String;
      
      // دریافت نقاط دسترسی مربوطه
      final apMaps = await db.query(
        'access_points',
        where: 'fingerprint_id = ?',
        whereArgs: [fingerprintId],
      );
      
      final accessPoints = apMaps.map((apMap) {
        return WifiReading(
          bssid: apMap['bssid'] as String,
          rssi: apMap['rssi'] as int,
          frequency: apMap['frequency'] as int?,
          ssid: apMap['ssid'] as String?,
        );
      }).toList();
      
      fingerprints.add(FingerprintEntry(
        id: fpMap['id'] as int?,
        fingerprintId: fingerprintId,
        latitude: fpMap['latitude'] as double,
        longitude: fpMap['longitude'] as double,
        zoneLabel: fpMap['zone_label'] as String?,
        accessPoints: accessPoints,
        createdAt: DateTime.parse(fpMap['created_at'] as String),
        deviceId: fpMap['device_id'] as String?,
      ));
    }
    
    return fingerprints;
  }

  /// دریافت اثرانگشت بر اساس شناسه
  Future<FingerprintEntry?> getFingerprintById(String fingerprintId) async {
    final db = await database;
    
    final fpMaps = await db.query(
      'fingerprints',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
      limit: 1,
    );
    
    if (fpMaps.isEmpty) return null;
    
    final fpMap = fpMaps.first;
    
    // دریافت نقاط دسترسی
    final apMaps = await db.query(
      'access_points',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
    );
    
    final accessPoints = apMaps.map((apMap) {
      return WifiReading(
        bssid: apMap['bssid'] as String,
        rssi: apMap['rssi'] as int,
        frequency: apMap['frequency'] as int?,
        ssid: apMap['ssid'] as String?,
      );
    }).toList();
    
    return FingerprintEntry(
      id: fpMap['id'] as int?,
      fingerprintId: fingerprintId,
      latitude: fpMap['latitude'] as double,
      longitude: fpMap['longitude'] as double,
      zoneLabel: fpMap['zone_label'] as String?,
      accessPoints: accessPoints,
      createdAt: DateTime.parse(fpMap['created_at'] as String),
      deviceId: fpMap['device_id'] as String?,
    );
  }

  /// حذف اثرانگشت
  Future<int> deleteFingerprint(String fingerprintId) async {
    final db = await database;
    
    // حذف خودکار نقاط دسترسی به دلیل CASCADE
    return await db.delete(
      'fingerprints',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
    );
  }

  /// تعداد کل اثرانگشت‌ها
  Future<int> getFingerprintCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM fingerprints');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// پاک کردن تمام داده‌ها
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('access_points');
    await db.delete('fingerprints');
    debugPrint('All fingerprints cleared');
  }

  /// بستن پایگاه داده
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}


