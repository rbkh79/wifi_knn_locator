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
        session_id TEXT,
        context_id TEXT,
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

    // جدول جلسات/مسیرها
    await db.execute('''
      CREATE TABLE training_sessions (
        session_id TEXT PRIMARY KEY,
        context_id TEXT,
        started_at TEXT NOT NULL,
        finished_at TEXT
      )
    ''');

    // جدول اسکن‌های Wi-Fi
    await db.execute('''
      CREATE TABLE wifi_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE wifi_scan_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id INTEGER NOT NULL,
        bssid TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        frequency INTEGER,
        ssid TEXT,
        FOREIGN KEY (scan_id) REFERENCES wifi_scans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_scan_timestamp ON wifi_scans(timestamp)');
    await db.execute('CREATE INDEX idx_scan_readings_scan_id ON wifi_scan_readings(scan_id)');

    // جدول تاریخچه موقعیت
    await db.execute('''
      CREATE TABLE location_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        zone_label TEXT,
        confidence REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_location_device ON location_history(device_id)');
    await db.execute('CREATE INDEX idx_location_timestamp ON location_history(timestamp)');

    // جدول اسکن‌های خام (بدون موقعیت)
    await db.execute('''
      CREATE TABLE raw_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        session_id TEXT,
        context_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE raw_scan_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_scan_id INTEGER NOT NULL,
        bssid TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        frequency INTEGER,
        ssid TEXT,
        FOREIGN KEY (raw_scan_id) REFERENCES raw_scans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_raw_scan_timestamp ON raw_scans(timestamp)');
    await db.execute('CREATE INDEX idx_raw_scan_device ON raw_scans(device_id)');

    // جداول اثرانگشت‌های سلولی (Cell Fingerprints)
    await db.execute('''
      CREATE TABLE cell_fingerprints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint_id TEXT UNIQUE NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        zone_label TEXT,
        session_id TEXT,
        context_id TEXT,
        created_at TEXT NOT NULL,
        device_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cell_towers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint_id TEXT NOT NULL,
        cell_id INTEGER,
        lac INTEGER,
        tac INTEGER,
        mcc INTEGER,
        mnc INTEGER,
        signal_strength INTEGER,
        network_type TEXT,
        psc INTEGER,
        pci INTEGER,
        FOREIGN KEY (fingerprint_id) REFERENCES cell_fingerprints(fingerprint_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_cell_fingerprint_id ON cell_fingerprints(fingerprint_id)');
    await db.execute('CREATE INDEX idx_cell_tower_fingerprint_id ON cell_towers(fingerprint_id)');
    await db.execute('CREATE INDEX idx_cell_tower_cell_id ON cell_towers(cell_id)');
    await db.execute('CREATE INDEX idx_cell_tower_mcc_mnc ON cell_towers(mcc, mnc)');
  }

  /// به‌روزرسانی پایگاه داده (در صورت تغییر نسخه)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _onCreateV2(db);
    }
    if (oldVersion < 3) {
      await _onUpgradeV3(db);
    }
    if (oldVersion < 4) {
      await _onUpgradeV4(db);
    }
    debugPrint('Database upgrade from $oldVersion to $newVersion');
  }

  Future<void> _onCreateV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wifi_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wifi_scan_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id INTEGER NOT NULL,
        bssid TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        frequency INTEGER,
        ssid TEXT,
        FOREIGN KEY (scan_id) REFERENCES wifi_scans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS location_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        zone_label TEXT,
        confidence REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgradeV3(Database db) async {
    // افزودن ستون‌های جدید به جدول اثرانگشت‌ها
    await db.execute('ALTER TABLE fingerprints ADD COLUMN session_id TEXT');
    await db.execute('ALTER TABLE fingerprints ADD COLUMN context_id TEXT');

    // ایجاد جدول جلسات اگر وجود ندارد
    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_sessions (
        session_id TEXT PRIMARY KEY,
        context_id TEXT,
        started_at TEXT NOT NULL,
        finished_at TEXT
      )
    ''');

    // ایجاد جدول raw scans
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raw_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        session_id TEXT,
        context_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS raw_scan_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_scan_id INTEGER NOT NULL,
        bssid TEXT NOT NULL,
        rssi INTEGER NOT NULL,
        frequency INTEGER,
        ssid TEXT,
        FOREIGN KEY (raw_scan_id) REFERENCES raw_scans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_raw_scan_timestamp ON raw_scans(timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_raw_scan_device ON raw_scans(device_id)');
  }

  Future<void> _onUpgradeV4(Database db) async {
    // ایجاد جداول اثرانگشت‌های سلولی
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cell_fingerprints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint_id TEXT UNIQUE NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        zone_label TEXT,
        session_id TEXT,
        context_id TEXT,
        created_at TEXT NOT NULL,
        device_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cell_towers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint_id TEXT NOT NULL,
        cell_id INTEGER,
        lac INTEGER,
        tac INTEGER,
        mcc INTEGER,
        mnc INTEGER,
        signal_strength INTEGER,
        network_type TEXT,
        psc INTEGER,
        pci INTEGER,
        FOREIGN KEY (fingerprint_id) REFERENCES cell_fingerprints(fingerprint_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_cell_fingerprint_id ON cell_fingerprints(fingerprint_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cell_tower_fingerprint_id ON cell_towers(fingerprint_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cell_tower_cell_id ON cell_towers(cell_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cell_tower_mcc_mnc ON cell_towers(mcc, mnc)');
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
            'session_id': fingerprint.sessionId,
            'context_id': fingerprint.contextId,
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
        sessionId: fpMap['session_id'] as String?,
        contextId: fpMap['context_id'] as String?,
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
      sessionId: fpMap['session_id'] as String?,
      contextId: fpMap['context_id'] as String?,
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
    await db.delete('wifi_scan_readings');
    await db.delete('wifi_scans');
    await db.delete('location_history');
    await db.delete('raw_scan_readings');
    await db.delete('raw_scans');
    await db.delete('training_sessions');
    await db.delete('cell_towers');
    await db.delete('cell_fingerprints');
    debugPrint('All fingerprints cleared');
  }

  /// بستن پایگاه داده
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // --- بخش مربوط به لاگ اسکن Wi-Fi ---
  Future<int> insertWifiScanLog(WifiScanLog log) async {
    final db = await database;
    return await db.transaction<int>((txn) async {
      final scanId = await txn.insert('wifi_scans', {
        'device_id': log.deviceId,
        'timestamp': log.timestamp.toIso8601String(),
      });

      for (final reading in log.readings) {
        await txn.insert('wifi_scan_readings', {
          'scan_id': scanId,
          'bssid': reading.bssid,
          'rssi': reading.rssi,
          'frequency': reading.frequency,
          'ssid': reading.ssid,
        });
      }

      return scanId;
    });
  }

  Future<List<WifiScanLog>> getRecentWifiScanLogs({
    required String deviceId,
    int limit = 20,
  }) async {
    final db = await database;
    final scans = await db.query(
      'wifi_scans',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    final logs = <WifiScanLog>[];
    for (final scan in scans) {
      final scanId = scan['id'] as int;
      final readingMaps = await db.query(
        'wifi_scan_readings',
        where: 'scan_id = ?',
        whereArgs: [scanId],
      );

      final readings = readingMaps
          .map(
            (e) => WifiScanLogEntry(
              id: e['id'] as int?,
              bssid: e['bssid'] as String,
              rssi: e['rssi'] as int,
              frequency: e['frequency'] as int?,
              ssid: e['ssid'] as String?,
            ),
          )
          .toList();

      logs.add(
        WifiScanLog(
          id: scanId,
          deviceId: scan['device_id'] as String,
          timestamp: DateTime.parse(scan['timestamp'] as String),
          readings: readings,
        ),
      );
    }

    return logs;
  }

  // --- بخش مربوط به تاریخچه موقعیت ---
  Future<int> insertLocationHistory(LocationHistoryEntry entry) async {
    final db = await database;
    return await db.insert('location_history', {
      'device_id': entry.deviceId,
      'latitude': entry.latitude,
      'longitude': entry.longitude,
      'zone_label': entry.zoneLabel,
      'confidence': entry.confidence,
      'timestamp': entry.timestamp.toIso8601String(),
    });
  }

  Future<List<LocationHistoryEntry>> getLocationHistory({
    required String deviceId,
    int limit = 50,
    bool ascending = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'location_history',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp ${ascending ? 'ASC' : 'DESC'}',
      limit: limit,
    );

    return rows
        .map(
          (row) => LocationHistoryEntry(
            id: row['id'] as int?,
            deviceId: row['device_id'] as String,
            latitude: row['latitude'] as double,
            longitude: row['longitude'] as double,
            zoneLabel: row['zone_label'] as String?,
            confidence: (row['confidence'] as num).toDouble(),
            timestamp: DateTime.parse(row['timestamp'] as String),
          ),
        )
        .toList();
  }

  /// دریافت تمام WiFi Scans (برای Export)
  Future<List<WifiScanLog>> getAllWifiScans() async {
    final db = await database;
    final scans = await db.query('wifi_scans', orderBy: 'timestamp DESC');

    final logs = <WifiScanLog>[];
    for (final scan in scans) {
      final scanId = scan['id'] as int;
      final readingMaps = await db.query(
        'wifi_scan_readings',
        where: 'scan_id = ?',
        whereArgs: [scanId],
      );

      final readings = readingMaps
          .map(
            (e) => WifiScanLogEntry(
              id: e['id'] as int?,
              bssid: e['bssid'] as String,
              rssi: e['rssi'] as int,
              frequency: e['frequency'] as int?,
              ssid: e['ssid'] as String?,
            ),
          )
          .toList();

      logs.add(
        WifiScanLog(
          id: scanId,
          deviceId: scan['device_id'] as String,
          timestamp: DateTime.parse(scan['timestamp'] as String),
          readings: readings,
        ),
      );
    }

    return logs;
  }

  /// دریافت readings یک WiFi Scan
  Future<List<WifiScanLogEntry>> getWifiScanReadings(int scanId) async {
    final db = await database;
    final readingMaps = await db.query(
      'wifi_scan_readings',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );

    return readingMaps
        .map(
          (e) => WifiScanLogEntry(
            id: e['id'] as int?,
            bssid: e['bssid'] as String,
            rssi: e['rssi'] as int,
            frequency: e['frequency'] as int?,
            ssid: e['ssid'] as String?,
          ),
        )
        .toList();
  }

  /// دریافت تمام Location History (برای Export)
  Future<List<LocationHistoryEntry>> getAllLocationHistory() async {
    final db = await database;
    final rows = await db.query('location_history', orderBy: 'timestamp DESC');

    return rows
        .map(
          (row) => LocationHistoryEntry(
            id: row['id'] as int?,
            deviceId: row['device_id'] as String,
            latitude: row['latitude'] as double,
            longitude: row['longitude'] as double,
            zoneLabel: row['zone_label'] as String?,
            confidence: (row['confidence'] as num).toDouble(),
            timestamp: DateTime.parse(row['timestamp'] as String),
          ),
        )
        .toList();
  }

  // --- جلسات و زمینه‌ها ---
  Future<void> upsertTrainingSession(TrainingSession session) async {
    final db = await database;
    await db.insert(
      'training_sessions',
      {
        'session_id': session.sessionId,
        'context_id': session.contextId,
        'started_at': session.startedAt.toIso8601String(),
        'finished_at': session.finishedAt?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> finishTrainingSession(String sessionId) async {
    final db = await database;
    await db.update(
      'training_sessions',
      {
        'finished_at': DateTime.now().toIso8601String(),
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<TrainingSession>> getTrainingSessions({int limit = 20}) async {
    final db = await database;
    final rows = await db.query(
      'training_sessions',
      orderBy: 'started_at DESC',
      limit: limit,
    );

    return rows
        .map(
          (row) => TrainingSession(
            sessionId: row['session_id'] as String,
            contextId: row['context_id'] as String?,
            startedAt: DateTime.parse(row['started_at'] as String),
            finishedAt: row['finished_at'] != null
                ? DateTime.tryParse(row['finished_at'] as String)
                : null,
          ),
        )
        .toList();
  }

  Future<List<String>> getAvailableContexts() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT context_id FROM fingerprints WHERE context_id IS NOT NULL AND context_id != ""',
    );
    final contextFromSessions = await db.rawQuery(
      'SELECT DISTINCT context_id FROM training_sessions WHERE context_id IS NOT NULL AND context_id != ""',
    );

    final contexts = <String>{};
    for (final row in rows) {
      contexts.add(row['context_id'] as String);
    }
    for (final row in contextFromSessions) {
      contexts.add(row['context_id'] as String);
    }
    return contexts.toList();
  }

  Future<List<FingerprintEntry>> getFingerprintsBySession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'fingerprints',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );

    final entries = <FingerprintEntry>[];
    for (final row in rows) {
      final fingerprintId = row['fingerprint_id'] as String;
      final apMaps = await db.query(
        'access_points',
        where: 'fingerprint_id = ?',
        whereArgs: [fingerprintId],
      );
      final accessPoints = apMaps
          .map(
            (apMap) => WifiReading(
              bssid: apMap['bssid'] as String,
              rssi: apMap['rssi'] as int,
              frequency: apMap['frequency'] as int?,
              ssid: apMap['ssid'] as String?,
            ),
          )
          .toList();

      entries.add(
        FingerprintEntry(
          id: row['id'] as int?,
          fingerprintId: fingerprintId,
          latitude: row['latitude'] as double,
          longitude: row['longitude'] as double,
          zoneLabel: row['zone_label'] as String?,
          sessionId: row['session_id'] as String?,
          contextId: row['context_id'] as String?,
          accessPoints: accessPoints,
          createdAt: DateTime.parse(row['created_at'] as String),
          deviceId: row['device_id'] as String?,
        ),
      );
    }
    return entries;
  }

  // --- ذخیره اسکن‌های خام ---
  Future<int> insertRawWifiScan(RawWifiScan scan) async {
    final db = await database;
    return await db.transaction<int>((txn) async {
      final rawScanId = await txn.insert('raw_scans', {
        'device_id': scan.deviceId,
        'timestamp': scan.timestamp.toIso8601String(),
        'session_id': scan.sessionId,
        'context_id': scan.contextId,
      });

      for (final reading in scan.readings) {
        await txn.insert('raw_scan_readings', {
          'raw_scan_id': rawScanId,
          'bssid': reading.bssid,
          'rssi': reading.rssi,
          'frequency': reading.frequency,
          'ssid': reading.ssid,
        });
      }

      return rawScanId;
    });
  }

  Future<List<RawWifiScan>> getRawScans({
    int limit = 50,
    String? sessionId,
    String? contextId,
  }) async {
    final db = await database;
    final filters = <String>[];
    final args = <Object?>[];
    if (sessionId != null) {
      filters.add('session_id = ?');
      args.add(sessionId);
    }
    if (contextId != null) {
      filters.add('context_id = ?');
      args.add(contextId);
    }

    final rows = await db.query(
      'raw_scans',
      where: filters.isNotEmpty ? filters.join(' AND ') : null,
      whereArgs: filters.isNotEmpty ? args : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    final scans = <RawWifiScan>[];
    for (final row in rows) {
      final rawScanId = row['id'] as int;
      final readingMaps = await db.query(
        'raw_scan_readings',
        where: 'raw_scan_id = ?',
        whereArgs: [rawScanId],
      );

      final readings = readingMaps
          .map(
            (e) => WifiReading(
              bssid: e['bssid'] as String,
              rssi: e['rssi'] as int,
              frequency: e['frequency'] as int?,
              ssid: e['ssid'] as String?,
            ),
          )
          .toList();

      scans.add(
        RawWifiScan(
          id: rawScanId,
          deviceId: row['device_id'] as String,
          timestamp: DateTime.parse(row['timestamp'] as String),
          sessionId: row['session_id'] as String?,
          contextId: row['context_id'] as String?,
          readings: readings,
        ),
      );
    }

    return scans;
  }

  // --- بخش مربوط به اثرانگشت‌های سلولی ---
  
  /// افزودن اثرانگشت سلولی جدید
  Future<int> insertCellFingerprint(CellFingerprintEntry fingerprint) async {
    final db = await database;
    
    try {
      await db.transaction((txn) async {
        // افزودن رکورد اصلی
        await txn.insert(
          'cell_fingerprints',
          {
            'fingerprint_id': fingerprint.fingerprintId,
            'latitude': fingerprint.latitude,
            'longitude': fingerprint.longitude,
            'zone_label': fingerprint.zoneLabel,
            'session_id': fingerprint.sessionId,
            'context_id': fingerprint.contextId,
            'created_at': fingerprint.createdAt.toIso8601String(),
            'device_id': fingerprint.deviceId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // افزودن دکل‌های مخابراتی
        for (final cell in fingerprint.cellTowers) {
          await txn.insert(
            'cell_towers',
            {
              'fingerprint_id': fingerprint.fingerprintId,
              'cell_id': cell.cellId,
              'lac': cell.lac,
              'tac': cell.tac,
              'mcc': cell.mcc,
              'mnc': cell.mnc,
              'signal_strength': cell.signalStrength,
              'network_type': cell.networkType,
              'psc': cell.psc,
              'pci': cell.pci,
            },
          );
        }
      });

      debugPrint('Cell fingerprint inserted: ${fingerprint.fingerprintId}');
      return 1;
    } catch (e) {
      debugPrint('Error inserting cell fingerprint: $e');
      rethrow;
    }
  }

  /// دریافت تمام اثرانگشت‌های سلولی
  Future<List<CellFingerprintEntry>> getAllCellFingerprints() async {
    final db = await database;
    
    final fingerprintMaps = await db.query('cell_fingerprints', orderBy: 'created_at DESC');
    
    final fingerprints = <CellFingerprintEntry>[];
    
    for (final fpMap in fingerprintMaps) {
      final fingerprintId = fpMap['fingerprint_id'] as String;
      
      // دریافت دکل‌های مخابراتی مربوطه
      final cellMaps = await db.query(
        'cell_towers',
        where: 'fingerprint_id = ?',
        whereArgs: [fingerprintId],
      );
      
      final cellTowers = cellMaps.map((cellMap) {
        return CellTowerInfo(
          cellId: cellMap['cell_id'] as int?,
          lac: cellMap['lac'] as int?,
          tac: cellMap['tac'] as int?,
          mcc: cellMap['mcc'] as int?,
          mnc: cellMap['mnc'] as int?,
          signalStrength: cellMap['signal_strength'] as int?,
          networkType: cellMap['network_type'] as String?,
          psc: cellMap['psc'] as int?,
          pci: cellMap['pci'] as int?,
        );
      }).toList();
      
      fingerprints.add(CellFingerprintEntry(
        id: fpMap['id'] as int?,
        fingerprintId: fingerprintId,
        latitude: fpMap['latitude'] as double,
        longitude: fpMap['longitude'] as double,
        zoneLabel: fpMap['zone_label'] as String?,
        sessionId: fpMap['session_id'] as String?,
        contextId: fpMap['context_id'] as String?,
        cellTowers: cellTowers,
        createdAt: DateTime.parse(fpMap['created_at'] as String),
        deviceId: fpMap['device_id'] as String?,
      ));
    }
    
    return fingerprints;
  }

  /// دریافت اثرانگشت سلولی بر اساس شناسه
  Future<CellFingerprintEntry?> getCellFingerprintById(String fingerprintId) async {
    final db = await database;
    
    final fpMaps = await db.query(
      'cell_fingerprints',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
      limit: 1,
    );
    
    if (fpMaps.isEmpty) return null;
    
    final fpMap = fpMaps.first;
    
    // دریافت دکل‌های مخابراتی
    final cellMaps = await db.query(
      'cell_towers',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
    );
    
    final cellTowers = cellMaps.map((cellMap) {
      return CellTowerInfo(
        cellId: cellMap['cell_id'] as int?,
        lac: cellMap['lac'] as int?,
        tac: cellMap['tac'] as int?,
        mcc: cellMap['mcc'] as int?,
        mnc: cellMap['mnc'] as int?,
        signalStrength: cellMap['signal_strength'] as int?,
        networkType: cellMap['network_type'] as String?,
        psc: cellMap['psc'] as int?,
        pci: cellMap['pci'] as int?,
      );
    }).toList();
    
    return CellFingerprintEntry(
      id: fpMap['id'] as int?,
      fingerprintId: fingerprintId,
      latitude: fpMap['latitude'] as double,
      longitude: fpMap['longitude'] as double,
      zoneLabel: fpMap['zone_label'] as String?,
      sessionId: fpMap['session_id'] as String?,
      contextId: fpMap['context_id'] as String?,
      cellTowers: cellTowers,
      createdAt: DateTime.parse(fpMap['created_at'] as String),
      deviceId: fpMap['device_id'] as String?,
    );
  }

  /// حذف اثرانگشت سلولی
  Future<int> deleteCellFingerprint(String fingerprintId) async {
    final db = await database;
    
    // حذف خودکار دکل‌ها به دلیل CASCADE
    return await db.delete(
      'cell_fingerprints',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
    );
  }

  /// تعداد کل اثرانگشت‌های سلولی
  Future<int> getCellFingerprintCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM cell_fingerprints');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// پاک کردن تمام اثرانگشت‌های سلولی
  Future<void> clearAllCellFingerprints() async {
    final db = await database;
    await db.delete('cell_towers');
    await db.delete('cell_fingerprints');
    debugPrint('All cell fingerprints cleared');
  }
}










