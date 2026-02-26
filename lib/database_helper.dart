import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ساده‌سازی دسترسی به جداول مورد نیاز پایان‌نامه
class DatabaseHelper {
  static Database? _db;
  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'localization_research.db');
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  static FutureOr<void> _onCreate(Database db, int version) async {
    // GPS history
    await db.execute('''
      CREATE TABLE gps_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT,
        timestamp TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL
      )
    ''');

    // Wi‑Fi fingerprints
    await db.execute('''
      CREATE TABLE wifi_fingerprint_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        rssi_vector TEXT NOT NULL, -- JSON array
        zone_label TEXT
      )
    ''');

    // BTS history
    await db.execute('''
      CREATE TABLE bts_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        cell_id INTEGER,
        lac INTEGER,
        signal_strength INTEGER,
        latitude REAL,
        longitude REAL
      )
    ''');

    // Hybrid estimation log
    await db.execute('''
      CREATE TABLE hybrid_estimation_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        wifi_lat REAL,
        wifi_lon REAL,
        bts_lat REAL,
        bts_lon REAL,
        hybrid_lat REAL,
        hybrid_lon REAL
      )
    ''');

    // Comparison log (errors)
    await db.execute('''
      CREATE TABLE comparison_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        gps_lat REAL,
        gps_lon REAL,
        bts_error REAL,
        wifi_error REAL,
        hybrid_error REAL
      )
    ''');
  }

  /// روش کمکی برای ذخیره سریع یک ردیف در هر جدول
  static Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return db.insert(table, values);
  }
}
