import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'app_database.dart';

/// Akses baca/tulis ke tabel `kv` dan `outbox`.
class StoreRepository {
  StoreRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db => _database.db;

  /* ---------- key/value ---------- */

  Future<String?> readRaw(String key) async {
    final db = await _db;
    final rows = await db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> writeRaw(String key, String value) async {
    final db = await _db;
    await db.insert(
      'kv',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String key) async {
    final db = await _db;
    await db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }

  Future<dynamic> readJson(String key, dynamic fallback) async {
    final raw = await readRaw(key);
    if (raw == null || raw.isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  Future<bool> writeJson(String key, Object? value) async {
    try {
      await writeRaw(key, jsonEncode(value));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> readJsonList(String key) async {
    final decoded = await readJson(key, <dynamic>[]);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /* ---------- outbox ---------- */

  Future<void> enqueue(OutboxEntry entry) async {
    final db = await _db;
    await db.insert(
      'outbox',
      {
        'table_name': entry.table,
        'row_id': entry.id,
        'payload': jsonEncode(entry.payload),
        'deleted': entry.deleted ? 1 : 0,
        'device_id': entry.deviceId,
        'attempts': entry.attempts,
        'last_error': entry.lastError,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OutboxEntry>> outboxEntries({String? table}) async {
    final db = await _db;
    final rows = await db.query(
      'outbox',
      where: table == null ? null : 'table_name = ?',
      whereArgs: table == null ? null : [table],
      orderBy: 'id ASC',
    );
    return rows.map(_entryFromRow).toList();
  }

  Future<int> outboxCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> removeOutbox(String table, String id) async {
    final db = await _db;
    await db.delete(
      'outbox',
      where: 'table_name = ? AND row_id = ?',
      whereArgs: [table, id],
    );
  }

  Future<void> clearOutbox() async {
    final db = await _db;
    await db.delete('outbox');
  }

  Future<void> markOutboxError(
    String table,
    String id,
    String error, {
    bool bumpAttempts = true,
  }) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE outbox SET last_error = ?, attempts = attempts + ? '
      'WHERE table_name = ? AND row_id = ?',
      [error, bumpAttempts ? 1 : 0, table, id],
    );
  }

  OutboxEntry _entryFromRow(Map<String, Object?> row) {
    Map<String, dynamic> payload = <String, dynamic>{};
    try {
      final decoded = jsonDecode((row['payload'] as String?) ?? '{}');
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      payload = <String, dynamic>{};
    }
    return OutboxEntry(
      table: (row['table_name'] as String?) ?? '',
      id: (row['row_id'] as String?) ?? '',
      payload: payload,
      deleted: (row['deleted'] as int? ?? 0) != 0,
      deviceId: (row['device_id'] as String?) ?? '',
      attempts: row['attempts'] as int? ?? 0,
      lastError: (row['last_error'] as String?) ?? '',
    );
  }
}
