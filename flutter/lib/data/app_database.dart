import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Penyimpanan lokal: tabel `kv` (mirip localStorage) dan `outbox` (antrean
/// sinkronisasi). Semua data POS tetap hidup di perangkat; server hanya salinan.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get db {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'ipomiepangsit_pos.db');
    final database = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            row_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            device_id TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            UNIQUE (table_name, row_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_outbox_table ON outbox (table_name, id)',
        );
      },
    );
    _db = database;
    return database;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
