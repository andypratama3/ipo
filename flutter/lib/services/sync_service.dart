import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/defaults.dart';
import '../data/store_repository.dart';
import '../models/models.dart';
import 'api_client.dart';

class SyncStatus {
  const SyncStatus({
    required this.enabled,
    required this.configured,
    required this.busy,
    required this.queued,
    required this.error,
    required this.lastAt,
    required this.deviceId,
  });

  final bool enabled;
  final bool configured;
  final bool busy;
  final int queued;
  final String error;
  final String lastAt;
  final String deviceId;

  String get label {
    if (!configured) return 'Lokal';
    if (busy) return 'Menyinkron…';
    if (error.isNotEmpty) return 'Gagal sinkron';
    if (queued > 0) return '$queued menunggu';
    return 'Tersinkron';
  }
}

typedef SyncRowsHandler = Future<void> Function(String table, List<SyncRow> rows);
typedef SyncEntriesProvider = List<Map<String, dynamic>> Function(String table);

/// Sinkronisasi dua arah dengan backend IPOS.
///
/// Kontrak server yang dipakai (lihat `ipo-backend/src/services/sync.js`):
/// - `GET  /api/sync/pull?table=&since=&sinceId=&limit=`
/// - `POST /api/sync/push` body `{ table, rows, deviceId }`
/// - `POST /api/orders` body `{ order, deviceId }`
/// - `DELETE /api/orders/:id` body `{ deviceId }`
class SyncService {
  SyncService({required this.api, required this.store});

  final ApiClient api;
  final StoreRepository store;

  static const _epoch = '1970-01-01T00:00:00.000Z';
  static const _limit = 1000;
  static const _pullInterval = Duration(seconds: 45);
  static const _pushDelay = Duration(milliseconds: 1500);
  static const _maxBackoff = Duration(minutes: 5);

  SyncRowsHandler? onRows;
  void Function(SyncStatus status)? onStatus;
  SyncEntriesProvider? getEntries;

  bool _started = false;
  bool _prepared = false;
  bool _busy = false;
  bool _enabled = true;
  bool _bootstrapChecked = false;
  String _deviceId = '';
  String _error = '';
  String _lastAt = '';

  Timer? _pullTimer;
  Timer? _pushTimer;
  Timer? _retryTimer;
  Duration _backoff = Duration.zero;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool get isConfigured => api.isConfigured;
  bool get isEnabled => _enabled;

  String get deviceId {
    if (_deviceId.isEmpty) _deviceId = 'device-${DateTime.now().microsecondsSinceEpoch}';
    return _deviceId;
  }

  /// Memuat id perangkat + preferensi sinkronisasi tanpa menyentuh jaringan.
  /// Dipanggil sebelum perubahan lokal pertama supaya baris yang diantrekan
  /// memakai id perangkat yang tetap (bukan id sekali pakai).
  Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;

    final savedDevice = await store.readRaw(kStorageKeys['syncDeviceId']!);
    if (savedDevice != null && savedDevice.trim().isNotEmpty) {
      _deviceId = savedDevice.trim();
    } else {
      _deviceId = 'device-${DateTime.now().microsecondsSinceEpoch}';
      await store.writeRaw(kStorageKeys['syncDeviceId']!, _deviceId);
    }

    final enabledRaw = await store.readRaw(kStorageKeys['syncEnabled']!);
    _enabled = enabledRaw != '0';
    _lastAt = await store.readRaw(kStorageKeys['syncLastAt']!) ?? '';
    await emit();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await prepare();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      if (online) {
        _backoff = Duration.zero;
        unawaited(syncNow());
      } else {
        unawaited(emit());
      }
    });

    if (isConfigured) unawaited(syncNow());
    _pullTimer = Timer.periodic(_pullInterval, (_) => unawaited(syncNow()));
  }

  Future<void> stop() async {
    _pullTimer?.cancel();
    _pushTimer?.cancel();
    _retryTimer?.cancel();
    await _connectivitySub?.cancel();
    _started = false;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await store.writeRaw(kStorageKeys['syncEnabled']!, value ? '1' : '0');
    if (value) {
      _backoff = Duration.zero;
      unawaited(syncNow());
    } else {
      _pushTimer?.cancel();
      _retryTimer?.cancel();
      await emit();
    }
  }

  Future<void> emit() async {
    final queued = await store.outboxCount();
    onStatus?.call(SyncStatus(
      enabled: _enabled,
      configured: isConfigured,
      busy: _busy,
      queued: queued,
      error: _error,
      lastAt: _lastAt,
      deviceId: deviceId,
    ));
  }

  /* ---------- antrean ---------- */

  Future<void> enqueueRow(String table, String id, Map<String, dynamic> payload) async {
    if (!_enabled) return;
    await store.enqueue(OutboxEntry(
      table: table,
      id: id,
      payload: payload,
      deleted: false,
      deviceId: deviceId,
    ));
    await emit();
    schedulePush();
  }

  Future<void> enqueueDelete(String table, String id) async {
    if (!_enabled) return;
    await store.enqueue(OutboxEntry(
      table: table,
      id: id,
      payload: {'id': id},
      deleted: true,
      deviceId: deviceId,
    ));
    await emit();
    schedulePush();
  }

  /// Dipakai tombol "Sinkron sekarang".
  Future<bool> syncNow() async {
    if (!_started || !_enabled || _busy) return false;
    if (!isConfigured) {
      await emit();
      return false;
    }
    final results = await Connectivity().checkConnectivity();
    if (results.every((result) => result == ConnectivityResult.none)) {
      await emit();
      return false;
    }
    _busy = true;
    _error = '';
    await emit();
    try {
      await _pull();
      final flushed = await _flush();
      await store.writeRaw(
        kStorageKeys['syncLastAt']!,
        DateTime.now().toUtc().toIso8601String(),
      );
      _lastAt = DateTime.now().toUtc().toIso8601String();
      return flushed;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _busy = false;
      await emit();
    }
  }

  void schedulePush() {
    if (!_started || !_enabled || !isConfigured) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, () => unawaited(syncNow()));
  }

  void _scheduleRetry() {
    if (!_started || !_enabled) return;
    _backoff = _backoff == Duration.zero
        ? _pushDelay
        : Duration(
            milliseconds: (_backoff.inMilliseconds * 2)
                .clamp(_pushDelay.inMilliseconds, _maxBackoff.inMilliseconds)
                .toInt(),
          );
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, () => unawaited(syncNow()));
  }

  /* ---------- tarik ---------- */

  Future<Set<String>> _pull() async {
    final emptyTables = <String>{};
    for (final table in kSyncTables) {
      try {
        final cursorKey = 'mpj_sync_cursor_$table';
        final rawCursor = await store.readRaw(cursorKey);
        var since = _epoch;
        var sinceId = '';
        var first = true;
        if (rawCursor != null && rawCursor.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawCursor);
            if (decoded is Map) {
              since = (decoded['since']?.toString() ?? _epoch);
              sinceId = (decoded['sinceId']?.toString() ?? '');
              first = false;
            }
          } catch (_) {
            // cursor rusak → mulai dari awal
          }
        }

        var received = 0;
        while (true) {
          final query = StringBuffer('/api/sync/pull?table=${Uri.encodeComponent(table)}')
            ..write('&limit=$kLimitForPull');
          if (since.isNotEmpty && since != _epoch) {
            query.write('&since=${Uri.encodeComponent(since)}');
            if (sinceId.isNotEmpty) {
              query.write('&sinceId=${Uri.encodeComponent(sinceId)}');
            }
          } else if (sinceId.isNotEmpty) {
            query.write('&sinceId=${Uri.encodeComponent(sinceId)}');
          }

          final body = await api.get(query.toString());
          final rawRows = body['rows'];
          final rows = <SyncRow>[];
          if (rawRows is List) {
            for (final item in rawRows) {
              if (item is Map) {
                rows.add(SyncRow.fromJson(table, Map<String, dynamic>.from(item)));
              }
            }
          }
          if (rows.isNotEmpty) {
            received += rows.length;
            await onRows?.call(table, rows);
          }

          final cursor = body['cursor'];
          if (cursor is Map) {
            since = cursor['since']?.toString() ?? since;
            sinceId = cursor['sinceId']?.toString() ?? sinceId;
            await store.writeRaw(
              cursorKey,
              jsonEncode({'since': since, 'sinceId': sinceId}),
            );
          }
          if (body['hasMore'] != true) break;
        }

        if (first && received == 0) emptyTables.add(table);
      } catch (error) {
        _error = error.toString();
      }
    }

    // Perangkat pertama menyambung server kosong: unggah daftar lokal.
    if (!_bootstrapChecked) {
      _bootstrapChecked = true;
      for (final table in emptyTables) {
        final entries = getEntries?.call(table) ?? const [];
        for (final entry in entries) {
          final id = entry['id']?.toString() ?? (table == 'settings' ? 'main' : '');
          if (id.isEmpty) continue;
          final payload = entry['payload'] is Map
              ? Map<String, dynamic>.from(entry['payload'] as Map)
              : <String, dynamic>{};
          if (payload.isEmpty) continue;
          await store.enqueue(OutboxEntry(
            table: table,
            id: id,
            payload: payload,
            deleted: false,
            deviceId: deviceId,
          ));
        }
      }
      await emit();
    }
    return emptyTables;
  }

  static const int kLimitForPull = _limit;

  /* ---------- kirim ---------- */

  Future<bool> _flush() async {
    final entries = await store.outboxEntries();
    if (entries.isEmpty) return true;

    final byTable = <String, List<OutboxEntry>>{};
    for (final entry in entries) {
      byTable.putIfAbsent(entry.table, () => []).add(entry);
    }

    for (final table in byTable.keys) {
      final rows = byTable[table]!;
      try {
        if (table == 'orders') {
          await _flushOrders(rows);
        } else {
          await api.post('/api/sync/push', {
            'table': table,
            'rows': rows
                .map((row) => {
                      'id': row.id,
                      'payload': row.payload,
                      'deleted': row.deleted,
                      'deviceId': deviceId,
                    })
                .toList(),
            'deviceId': deviceId,
          });
          for (final row in rows) {
            await store.removeOutbox(table, row.id);
          }
        }
        _error = '';
        _backoff = Duration.zero;
      } on ApiException catch (error) {
        if (error.status == 403) {
          // Peran tidak boleh menulis tabel ini: buang agar transaksi lain lancar.
          for (final row in rows) {
            await store.removeOutbox(table, row.id);
          }
          _error = error.message;
          continue;
        }
        _error = error.message;
        for (final row in rows) {
          await store.markOutboxError(table, row.id, error.message);
        }
        _scheduleRetry();
        await emit();
        return false;
      }
    }
    await emit();
    return true;
  }

  Future<void> _flushOrders(List<OutboxEntry> rows) async {
    for (final row in rows) {
      if (row.deleted) {
        try {
          await api.delete(
            '/api/orders/${Uri.encodeComponent(row.id)}',
            {'deviceId': deviceId},
          );
        } on ApiException catch (error) {
          if (error.status != 404) rethrow;
        }
        await store.removeOutbox('orders', row.id);
        continue;
      }
      await api.post('/api/orders', {
        'order': row.payload,
        'deviceId': deviceId,
      });
      await store.removeOutbox('orders', row.id);
    }
  }

  /// Dipakai fitur "Kirim ulang semua data ke server".
  Future<void> enqueueAll(List<SyncRow> rows) async {
    for (final row in rows) {
      await store.enqueue(OutboxEntry(
        table: row.table,
        id: row.id,
        payload: row.payload,
        deleted: row.deleted,
        deviceId: deviceId,
      ));
    }
    await emit();
    schedulePush();
  }
}
