import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import '../core/defaults.dart';
import '../core/format.dart';
import '../core/ids.dart';
import '../data/store_repository.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/backup_service.dart';
import '../services/print_service.dart';
import '../services/qris_service.dart';
import '../services/report_service.dart';
import '../services/sync_service.dart';

class _Row {
  const _Row(this.id, this.payload);
  final String id;
  final Map<String, dynamic> payload;
}

/// Satu sumber kebenaran untuk seluruh aplikasi — padanan `state` + fungsi di
/// `pos.js`. Semua layar membaca dari sini lewat `provider`.
class AppController extends ChangeNotifier {
  AppController({
    StoreRepository? store,
    ApiClient? api,
    SyncService? sync,
    PrintService? printer,
    ReportService? reports,
    BackupService? backup,
  })  : store = store ?? StoreRepository(),
        api = api ?? ApiClient(),
        printer = printer ?? PrintService(),
        reports = reports ?? ReportService(),
        backup = backup ?? BackupService() {
    this.sync = sync ?? SyncService(api: this.api, store: this.store);
  }

  final StoreRepository store;
  final ApiClient api;
  late final SyncService sync;
  final PrintService printer;
  final ReportService reports;
  final BackupService backup;

  /* ---------- data ---------- */
  List<Product> products = [];
  List<Order> orders = [];
  AppSettings settings = AppSettings();
  List<Category> categories = [];
  List<PendingOrder> pendingOrders = [];
  List<OnlineOrder> onlineOrders = [];
  List<LocalUser> localUsers = [];
  List<ServerUser>? serverUsers;
  String userListStatus = '';
  List<Snapshot> snapshots = [];
  SessionUser? user;

  /* ---------- keranjang & layar kasir ---------- */
  List<CartItem> cart = [];
  String category = 'semua';
  String search = '';
  String menuFilter = 'all';
  String orderType = 'dine-in';
  String selectedPayment = 'cash';
  String tableNumber = '';
  String cartNote = '';
  int cartDiscount = 0;
  String cartTab = 'cart';
  String onlineStatusFilter = 'baru';
  String onlinePlatformFilter = 'all';
  String? cartNoteOpenId;
  String? editingProductId;
  Order? currentOrder;

  /* ---------- aplikasi ---------- */
  bool loading = true;
  String theme = 'light';
  String apiBase = '';
  bool syncEnabled = true;
  SyncStatus? syncStatus;
  String lastExport = '';
  String? storageProblem;
  DateTime now = DateTime.now();

  /// Callback toast dipasang oleh `main.dart` (ScaffoldMessenger).
  void Function(String message)? onToast;
  void Function(String? problem)? onStorageAlert;

  Timer? _clockTimer;
  Timer? _midnightTimer;
  int _ordersSinceSnapshot = 0;
  int _snapshotSeq = 0;
  bool _applyingRemote = false;
  bool _initialized = false;
  bool _remoteToastSeen = false;

  final Map<String, Set<String>> _knownIds = {};
  final Map<String, Map<String, String>> _knownJson = {};

  bool get isOwner => user?.isOwner ?? false;
  bool get isConfigured => apiBase.isNotEmpty;
  bool get hasToken => api.token.isNotEmpty;

  /// Akun dikelola server saat alamat server & token login tersedia.
  bool get accountsFromServer => apiBase.isNotEmpty && api.token.isNotEmpty;
  int get cartCount => cart.fold(0, (sum, item) => sum + item.qty);

  /* ======================================================================
     INISIALISASI
     ====================================================================== */

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    theme = await store.readRaw(kStorageKeys['theme']!) == 'dark' ? 'dark' : 'light';
    apiBase = ApiClient.normalizeBase(
      await store.readRaw(kStorageKeys['apiBase']!) ?? '',
    );
    final token = await store.readRaw(kStorageKeys['apiToken']!) ?? '';
    api.configure(baseUrl: apiBase, token: token);

    // `null` sebagai fallback membedakan "belum pernah disimpan" dari
    // "tersimpan sebagai daftar kosong" — sama seperti `load()` di pos.js.
    settings = _readSettings(await store.readJson(kStorageKeys['settings']!, null));
    products = _readProducts(await store.readJson(kStorageKeys['products']!, null));
    categories = _readCategories(
      await store.readJson(kStorageKeys['categories']!, null),
    );
    orders = _readOrders(await store.readJson(kStorageKeys['orders']!, null));
    pendingOrders = _readPending(
      await store.readJson(kStorageKeys['pending']!, null),
    );
    onlineOrders = _readOnline(await store.readJson(kStorageKeys['online']!, null));
    localUsers = _readUsers(await store.readJson(kStorageKeys['users']!, null));
    snapshots = _readSnapshots(
      await store.readJson(kStorageKeys['snapshots']!, null),
    );
    lastExport = await store.readRaw(kStorageKeys['lastExport']!) ?? '';
    cartTab = _normalizeCartTab(
      await store.readRaw(kStorageKeys['cartTab']!) ?? 'cart',
    );

    final cartData = await store.readJson(
      kStorageKeys['cartData']!,
      <String, dynamic>{},
    );
    _restoreCart(cartData);

    // Muat id perangkat & status sinkronisasi lebih dulu agar perubahan lokal
    // pertama (mis. pembaruan katalog) tidak memakai id perangkat sekali pakai.
    await sync.prepare();
    final catalogUpdated = await _applyCatalogUpdate();
    await _enforceSnapshotLimit();
    // Sama seperti renderQueues() di web: kode ambil untuk pesanan "siap"
    // dipastikan ada sejak aplikasi dimuat, bukan hanya setelah tarik data.
    if (_ensurePickupCodes()) {
      await store.writeJson(
        kStorageKeys['online']!,
        onlineOrders.map((order) => order.toJson()).toList(),
      );
    }

    _resetKnown();
    _wireSync();

    final restored = await _restoreSession();
    if (!restored) {
      // Sesi tidak ada / kedaluwarsa: layar login tampil lewat `user == null`.
    }

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      now = DateTime.now();
      notifyListeners();
    });
    _scheduleMidnight();

    await sync.start();
    if (catalogUpdated) {
      _toast(
        'Katalog menu diperbarui: ${formatNumber(products.length)} menu. '
        'Riwayat transaksi tetap utuh.',
      );
    }

    loading = false;
    notifyListeners();
  }

  void _wireSync() {
    sync.getEntries = _entriesForTable;
    sync.onRows = _applyRemoteRows;
    sync.onStatus = (status) {
      syncStatus = status;
      notifyListeners();
    };
    syncEnabled = sync.isEnabled;
  }

  /* ======================================================================
     PEMBACAAN DATA LOKAL (toleran terhadap data rusak)
     ====================================================================== */

  AppSettings _readSettings(dynamic raw) {
    if (raw is Map) {
      return AppSettings.fromJson(Map<String, dynamic>.from(raw));
    }
    return AppSettings();
  }

  List<Product> _readProducts(dynamic raw) {
    if (raw is! List) return defaultProducts();
    return raw
        .whereType<Map>()
        .map((row) => Product.fromJson(Map<String, dynamic>.from(row)))
        .where((product) => product.id.isNotEmpty && product.name.isNotEmpty)
        .toList();
  }

  List<Category> _readCategories(dynamic raw) {
    if (raw is! List || raw.isEmpty) return defaultCategories();
    return _normalizeCategories(raw);
  }

  List<Category> _normalizeCategories(dynamic raw) {
    if (raw is! List || raw.isEmpty) return defaultCategories();
    final list = raw
        .whereType<Map>()
        .map((row) => Category.fromJson(Map<String, dynamic>.from(row)))
        .where((entry) => entry.id.isNotEmpty)
        .map((entry) {
      final label = entry.label.trim().isEmpty ? entry.id : entry.label.trim();
      return Category(
        id: entry.id,
        label: label.length > 24 ? label.substring(0, 24) : label,
        emoji: entry.emoji.trim().isEmpty
            ? guessCategoryEmoji(label)
            : normalizeEmoji(entry.emoji),
      );
    }).toList();
    return list.isEmpty ? defaultCategories() : list;
  }

  List<Order> _readOrders(dynamic raw) {
    if (raw is! List) return [];
    final used = <String>{};
    final result = <Order>[];
    for (final entry in raw.whereType<Map>()) {
      final order = Order.fromJson(Map<String, dynamic>.from(entry));
      if (order.id.isEmpty) order.id = 'MPJ-DIPULIH-${used.length + 1}';
      var id = order.id;
      var suffix = 2;
      while (used.contains(id)) {
        id = '${order.id}-${suffix++}';
      }
      order.id = id;
      used.add(id);
      if (safeDate(order.createdAt) == null) {
        order.createdAt = DateTime.now().toUtc().toIso8601String();
      }
      result.add(order);
    }
    return result;
  }

  List<PendingOrder> _readPending(dynamic raw) {
    if (raw is! List) return [];
    return _normalizePending(raw);
  }

  List<OnlineOrder> _readOnline(dynamic raw) {
    if (raw is! List) return dummyOnlineOrders();
    return raw
        .whereType<Map>()
        .map((row) => OnlineOrder.fromJson(Map<String, dynamic>.from(row)))
        .where((entry) => entry.id.isNotEmpty)
        .toList();
  }

  List<LocalUser> _readUsers(dynamic raw) {
    if (raw is! List || raw.isEmpty) return defaultLocalUsers();
    final users = raw
        .whereType<Map>()
        .map((row) => LocalUser.fromJson(Map<String, dynamic>.from(row)))
        .where((entry) => entry.username.isNotEmpty && entry.password.isNotEmpty)
        .toList();
    return users.isEmpty ? defaultLocalUsers() : users;
  }

  List<Snapshot> _readSnapshots(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((row) => Snapshot.fromJson(Map<String, dynamic>.from(row)))
        .where((entry) => entry.id.isNotEmpty)
        .toList();
  }

  List<PendingOrder> _normalizePending(dynamic raw) {
    if (raw is! List) return [];
    final used = <String>{};
    final result = <PendingOrder>[];
    for (var index = 0; index < raw.length; index += 1) {
      final entry = raw[index];
      if (entry is! Map) continue;
      final order = PendingOrder.fromJson(Map<String, dynamic>.from(entry));
      if (order.items.isEmpty) continue;
      var id = order.id.isEmpty ? 'HOLD-DIPULIH-${index + 1}' : order.id;
      var suffix = 2;
      while (used.contains(id)) {
        id = '${order.id}-${suffix++}';
      }
      order.id = id;
      used.add(id);
      result.add(order);
    }
    return result;
  }

  void _restoreCart(dynamic raw) {
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final items = <CartItem>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final entry in rawItems.whereType<Map>()) {
        final item = CartItem.fromJson(Map<String, dynamic>.from(entry));
        if (item.productId.isEmpty) continue;
        items.add(item);
      }
    }
    cart = items;
    cartDiscount = asInt(data['discount']).clamp(0, 1 << 31);
    orderType = data['orderType'] == 'takeaway' ? 'takeaway' : 'dine-in';
    tableNumber = asText(data['tableNumber']);
    cartNote = asText(data['note']);
  }

  /* ======================================================================
     KATALOG BAWAAN & CADANGAN
     ====================================================================== */

  Future<bool> _applyCatalogUpdate() async {
    final storedVersion = asInt(
      await store.readRaw(kStorageKeys['catalog']!) ?? '0',
    );
    final hasStoredProducts =
        (await store.readRaw(kStorageKeys['products']!)) != null;
    if (storedVersion >= kCatalogVersion) return false;
    if (hasStoredProducts) {
      await takeSnapshot('Sebelum katalog menu diperbarui');
    }
    products = defaultProducts();
    categories = defaultCategories();
    category = 'semua';
    search = '';
    menuFilter = 'all';
    await _persist('products', products);
    await _persist('categories', categories);
    await store.writeRaw(kStorageKeys['catalog']!, '$kCatalogVersion');
    return true;
  }

  Future<Snapshot?> takeSnapshot(String reason) async {
    final payload = buildBackupPayload();
    String json;
    try {
      json = jsonEncode(payload);
    } catch (_) {
      return null;
    }
    if (json.length > 600 * 1024) return null;
    _snapshotSeq += 1;
    final snapshot = Snapshot(
      id: 'snap-${DateTime.now().millisecondsSinceEpoch}-$_snapshotSeq',
      at: DateTime.now().toUtc().toIso8601String(),
      reason: reason,
      ordersCount: orders.length,
      data: payload,
    );
    snapshots = [snapshot, ...snapshots].take(kSnapshotLimit).toList();
    await store.writeJson(
      kStorageKeys['snapshots']!,
      snapshots.map((entry) => entry.toJson()).toList(),
    );
    notifyListeners();
    return snapshot;
  }

  Future<void> _autoSnapshot(String reason) async {
    if (snapshots.isNotEmpty && snapshots.first.ordersCount == orders.length) {
      return;
    }
    await takeSnapshot(reason);
  }

  void _noteOrderSaved() {
    _ordersSinceSnapshot += 1;
    if (_ordersSinceSnapshot >= kSnapshotEveryOrders) {
      _ordersSinceSnapshot = 0;
      unawaited(_autoSnapshot('Otomatis — tiap $kSnapshotEveryOrders transaksi'));
    }
  }

  Future<void> _enforceSnapshotLimit() async {
    if (snapshots.length <= kSnapshotLimit) return;
    snapshots = snapshots.take(kSnapshotLimit).toList();
    await store.writeJson(
      kStorageKeys['snapshots']!,
      snapshots.map((entry) => entry.toJson()).toList(),
    );
  }

  Future<void> takeSnapshotNow() async {
    final snapshot = await takeSnapshot('Manual');
    _toast(
      snapshot != null
          ? 'Cadangan lokal tersimpan di perangkat.'
          : 'Penyimpanan penuh — cadangan dilewati, data utama tetap aman.',
    );
  }

  Future<void> restoreSnapshot(String id) async {
    final snapshot = snapshots.where((entry) => entry.id == id).firstOrNull;
    if (snapshot == null) {
      _toast('Cadangan tidak ditemukan.');
      return;
    }
    await takeSnapshot('Cadangan sebelum kembalikan');
    await applyBackupPayload(snapshot.data);
    _toast('Data dikembalikan dari cadangan.');
  }

  Future<void> deleteSnapshot(String id) async {
    snapshots = snapshots.where((entry) => entry.id != id).toList();
    await store.writeJson(
      kStorageKeys['snapshots']!,
      snapshots.map((entry) => entry.toJson()).toList(),
    );
    notifyListeners();
    _toast('Cadangan dihapus.');
  }

  Map<String, dynamic> buildBackupPayload() => backup.buildPayload(
        products: products,
        orders: orders,
        settings: settings,
        categories: categories,
        pendingOrders: pendingOrders,
        onlineOrders: onlineOrders,
      );

  Future<void> applyBackupPayload(Map<String, dynamic> data) async {
    final rawProducts = data['products'];
    final rawOrders = data['orders'];
    if (rawProducts is List) products = _readProducts(rawProducts);
    if (rawOrders is List) orders = _readOrders(rawOrders);
    if (data['settings'] is Map) {
      settings = AppSettings.fromJson(
        Map<String, dynamic>.from(data['settings'] as Map),
      );
    }
    categories = _normalizeCategories(data['categories']);
    if (data['pendingOrders'] is List) {
      pendingOrders = _normalizePending(data['pendingOrders']);
    }
    if (data['onlineOrders'] is List) {
      onlineOrders = _readOnline(data['onlineOrders']);
      _ensurePickupCodes();
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> exportBackup() async {
    final payload = buildBackupPayload();
    await backup.shareBackup(
      payload: payload,
      businessName: settings.businessName,
    );
    lastExport = DateTime.now().toUtc().toIso8601String();
    await store.writeRaw(kStorageKeys['lastExport']!, lastExport);
    notifyListeners();
  }

  Future<void> importBackup() async {
    try {
      final data = await backup.pickBackup();
      if (data == null) return;
      if (data['products'] is! List || data['orders'] is! List) {
        _toast('File backup tidak valid.');
        return;
      }
      await takeSnapshot('Cadangan sebelum import');
      await applyBackupPayload(data);
      _toast('Backup berhasil diimpor.');
    } catch (_) {
      _toast('File backup tidak valid.');
    }
  }

  /* ======================================================================
     PERSISTENSI + OUTBOX
     ====================================================================== */

  List<_Row> _entriesFor(String key, Object? value) {
    if (key == 'settings') {
      if (value is Map) {
        return [_Row('main', Map<String, dynamic>.from(value))];
      }
      return const [];
    }
    if (value is List) {
      final rows = <_Row>[];
      for (final entry in value.whereType<Map>()) {
        final payload = Map<String, dynamic>.from(entry);
        final id = asText(payload['id']);
        if (id.isEmpty) continue;
        rows.add(_Row(id, payload));
      }
      return rows;
    }
    return const [];
  }

  List<Map<String, dynamic>> _entriesForTable(String table) {
    final key = kSyncTableByKey.entries
        .where((entry) => entry.value == table)
        .map((entry) => entry.key)
        .firstOrNull;
    if (key == null) return const [];
    final value = _valueFor(key);
    return _entriesFor(key, value)
        .map((row) => {'id': row.id, 'payload': row.payload})
        .toList();
  }

  Object? _valueFor(String key) {
    switch (key) {
      case 'products':
        return products;
      case 'categories':
        return categories;
      case 'settings':
        return settings;
      case 'orders':
        return orders;
      case 'pending':
        return pendingOrders;
      case 'online':
        return onlineOrders;
      default:
        return null;
    }
  }

  bool _canWrite(String table) {
    if (table == 'products' || table == 'categories' || table == 'settings') {
      return isOwner;
    }
    return true;
  }

  void _resetKnown() {
    for (final key in kSyncTableByKey.keys) {
      final rows = _entriesFor(key, _valueFor(key));
      _knownIds[key] = rows.map((row) => row.id).toSet();
      _knownJson[key] = {for (final row in rows) row.id: jsonEncode(row.payload)};
    }
  }

  Future<void> _persist(String key, Object? value, {bool enqueue = true}) async {
    await store.writeJson(kStorageKeys[key]!, value);
    final table = kSyncTableByKey[key];
    if (table == null) return;
    final rows = _entriesFor(key, value);
    final nextIds = rows.map((row) => row.id).toSet();
    final nextJson = {for (final row in rows) row.id: jsonEncode(row.payload)};

    if (enqueue && !_applyingRemote && sync.isEnabled && _canWrite(table)) {
      final previousJson = _knownJson[key] ?? const <String, String>{};
      for (final row in rows) {
        if (previousJson[row.id] != nextJson[row.id]) {
          await sync.enqueueRow(table, row.id, row.payload);
        }
      }
      final previousIds = _knownIds[key] ?? const <String>{};
      for (final id in previousIds.difference(nextIds)) {
        await sync.enqueueDelete(table, id);
      }
    }
    _knownIds[key] = nextIds;
    _knownJson[key] = nextJson;
  }

  Future<void> _persistAll() async {
    await _persist('products', products);
    await _persist('categories', categories);
    await _persist('settings', settings);
    await _persist('orders', orders);
    await _persist('pending', pendingOrders);
    await _persist('online', onlineOrders);
  }

  Future<void> _saveCart() async {
    await store.writeJson(kStorageKeys['cartData']!, {
      'items': cart.map((item) => item.toJson()).toList(),
      'discount': cartDiscount,
      'orderType': orderType,
      'tableNumber': tableNumber,
      'note': cartNote,
    });
  }

  Future<void> _applyRemoteRows(String table, List<SyncRow> rows) async {
    if (rows.isEmpty) return;
    final key = kSyncTableByKey.entries
        .where((entry) => entry.value == table)
        .map((entry) => entry.key)
        .firstOrNull;
    if (key == null) return;
    var changed = false;
    _applyingRemote = true;
    try {
      if (table == 'settings') {
        const identityKeys = ['businessName', 'businessAddress', 'businessPhone'];
        for (final row in rows) {
          if (row.deleted || row.payload.isEmpty) continue;
          final incoming = Map<String, dynamic>.from(row.payload);
          for (final identity in identityKeys) {
            final localValue = asText(_settingValue(identity));
            final remoteValue = asText(incoming[identity]);
            if (remoteValue.isEmpty && localValue.isNotEmpty) {
              incoming[identity] = localValue;
            }
          }
          final merged = AppSettings.fromJson({
            ...settings.toJson(),
            ...incoming,
          });
          if (jsonEncode(merged.toJson()) != jsonEncode(settings.toJson())) {
            settings = merged;
            changed = true;
          }
        }
        if (changed) {
          await store.writeJson(kStorageKeys['settings']!, settings.toJson());
          _resetKnownKey('settings');
        }
        if (!changed) return;
      } else {
        final current = _valueFor(key);
        final byId = <String, Map<String, dynamic>>{};
        if (current is List) {
          for (final entry in current) {
            if (entry is Product) byId[entry.id] = entry.toJson();
            if (entry is Category) byId[entry.id] = entry.toJson();
            if (entry is Order) byId[entry.id] = entry.toJson();
            if (entry is PendingOrder) byId[entry.id] = entry.toJson();
            if (entry is OnlineOrder) byId[entry.id] = entry.toJson();
          }
        }
        for (final row in rows) {
          if (row.id.isEmpty) continue;
          if (row.deleted || row.payload.isEmpty) {
            if (byId.remove(row.id) != null) changed = true;
            continue;
          }
          final existing = byId[row.id];
          if (existing == null ||
              jsonEncode(existing) != jsonEncode(row.payload)) {
            byId[row.id] = row.payload;
            changed = true;
          }
        }
        if (!changed) return;
        final merged = byId.values.toList();
        switch (table) {
          case 'products':
            products = _readProducts(merged);
            break;
          case 'categories':
            categories = _normalizeCategories(merged);
            break;
          case 'orders':
            orders = _readOrders(merged);
            break;
          case 'pending_orders':
            pendingOrders = _normalizePending(merged);
            break;
          case 'online_orders':
            onlineOrders = merged
                .map((row) => OnlineOrder.fromJson(row))
                .where((entry) => entry.id.isNotEmpty)
                .toList();
            _ensurePickupCodes();
            break;
        }
        await store.writeJson(kStorageKeys[key]!, _valueFor(key));
        _resetKnownKey(key);
      }
    } catch (_) {
      return;
    } finally {
      _applyingRemote = false;
    }
    notifyListeners();
    final foreign = rows.any(
      (row) =>
          row.deviceId != null &&
          row.deviceId!.isNotEmpty &&
          row.deviceId != sync.deviceId,
    );
    if (foreign && !_remoteToastSeen) {
      _remoteToastSeen = true;
      _toast('Data diperbarui dari perangkat lain.');
    }
  }

  dynamic _settingValue(String key) {
    switch (key) {
      case 'businessName':
        return settings.businessName;
      case 'businessAddress':
        return settings.businessAddress;
      case 'businessPhone':
        return settings.businessPhone;
      default:
        return '';
    }
  }

  void _resetKnownKey(String key) {
    final rows = _entriesFor(key, _valueFor(key));
    _knownIds[key] = rows.map((row) => row.id).toSet();
    _knownJson[key] = {for (final row in rows) row.id: jsonEncode(row.payload)};
  }

  /* ======================================================================
     SESI & TEMA
     ====================================================================== */

  Future<String?> login(String usernameRaw, String password) async {
    final username = usernameRaw.trim().toLowerCase();
    if (apiBase.isNotEmpty) {
      try {
        final body = await api.post('/api/auth/login', {
          'username': username,
          'password': password,
        });
        final token = asText(body['token']);
        final serverUser =
            body['user'] is Map ? Map<String, dynamic>.from(body['user'] as Map) : {};
        api.setToken(token);
        await store.writeRaw(kStorageKeys['apiToken']!, token);
        serverUsers = null;
        userListStatus = '';
        await _loginAsUser(
          username: asText(serverUser['username'], fallback: username),
          name: asText(
            serverUser['displayName'],
            fallback: asText(serverUser['name'], fallback: username),
          ),
          role: asText(serverUser['role'], fallback: 'Kasir'),
        );
        return null;
      } on ApiException catch (error) {
        if (error.status == 401 || error.status == 400) {
          return 'Nama pengguna atau sandi salah.';
        }
        return 'Tidak bisa menghubungi server. Periksa internet atau alamat server di Pengaturan.';
      }
    }

    final local = findLocalUser(username);
    if (local == null || !local.active || password != local.password) {
      return 'Nama pengguna atau sandi salah. Akun bawaan: pemilik / 1234.';
    }
    await _loginAsUser(
      username: local.username,
      name: local.name,
      role: local.role,
    );
    return null;
  }

  Future<void> _loginAsUser({
    required String username,
    required String name,
    required String role,
  }) async {
    final loginAt = DateTime.now().millisecondsSinceEpoch;
    user = SessionUser(
      username: username,
      name: name,
      role: role == 'Pemilik' ? 'Pemilik' : 'Kasir',
      loginAt: loginAt,
      loginDay: _localDayKey(loginAt),
      loginMinute: _localMinuteOfDay(loginAt),
    );
    await store.writeJson(kStorageKeys['session']!, user!.toJson());
    _scheduleMidnight();
    notifyListeners();
    _toast('Selamat datang, $name.');
    if (api.isConfigured) unawaited(sync.syncNow());
  }

  Future<void> logout({bool notify = true}) async {
    await _autoSnapshot('Cadangan sebelum logout');
    await store.remove(kStorageKeys['session']!);
    api.setToken('');
    await store.remove(kStorageKeys['apiToken']!);
    user = null;
    currentOrder = null;
    // Keranjang sengaja TIDAK dikosongkan: pesanan yang sedang dibayar harus
    // selamat melewati pergantian sesi.
    if (notify) notifyListeners();
  }

  LocalUser? findLocalUser(String username) {
    final key = username.trim().toLowerCase();
    return localUsers.where((entry) => entry.username == key).firstOrNull;
  }

  Future<bool> _restoreSession() async {
    final raw = await store.readJson(kStorageKeys['session']!, null);
    if (raw is! Map) return false;
    final session = SessionUser.fromJson(Map<String, dynamic>.from(raw));
    if (session.name.isEmpty) return false;
    if (session.loginAt <= 0) {
      session.loginAt = DateTime.now().millisecondsSinceEpoch;
    }
    if (session.loginDay.isEmpty) session.loginDay = _localDayKey(session.loginAt);
    if (session.loginMinute < 0) session.loginMinute = _localMinuteOfDay(session.loginAt);
    user = session;
    if (_sessionExpired()) {
      await logout(notify: false);
      _toast('Sesi berakhir pukul 00.00 — silakan masuk kembali.');
      return false;
    }
    await store.writeJson(kStorageKeys['session']!, session.toJson());
    return true;
  }

  bool _sessionExpired() {
    final active = user;
    if (active == null) return false;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return _localDayKey(stamp) != active.loginDay ||
        _localMinuteOfDay(stamp) < active.loginMinute;
  }

  Future<void> checkSessionTimeout() async {
    if (user == null) return;
    if (_sessionExpired()) {
      await logout();
      _toast('Sesi berakhir pukul 00.00 — silakan masuk kembali.');
    }
  }

  String _localDayKey(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month}-${date.day}';
  }

  int _localMinuteOfDay(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return date.hour * 60 + date.minute;
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final current = DateTime.now();
    final next = DateTime(current.year, current.month, current.day + 1);
    _midnightTimer = Timer(next.difference(current), () {
      unawaited(checkSessionTimeout());
      _scheduleMidnight();
    });
  }

  Future<void> toggleTheme() async {
    theme = theme == 'dark' ? 'light' : 'dark';
    await store.writeRaw(kStorageKeys['theme']!, theme);
    notifyListeners();
  }

  /* ======================================================================
     PRODUK, KATEGORI, PENGATURAN
     ====================================================================== */

  Future<void> setSearch(String value) {
    search = value.trim().toLowerCase();
    notifyListeners();
    return Future.value();
  }

  Future<void> setCategory(String value) {
    category = value;
    notifyListeners();
    return Future.value();
  }

  Future<void> setMenuFilter(String value) {
    menuFilter = value;
    notifyListeners();
    return Future.value();
  }

  Product? productById(String id) =>
      products.where((entry) => entry.id == id).firstOrNull;

  Category? categoryById(String id) =>
      categories.where((entry) => entry.id == id).firstOrNull;

  String categoryLabel(String id) {
    if (id == 'semua') return 'Semua';
    return categoryById(id)?.label ?? id;
  }

  String categoryEmoji(String id) {
    if (id == 'semua') return '🍽️';
    return categoryById(id)?.emoji ?? '🍽️';
  }

  int unitPrice(Product product) => product.price;

  ProductAvailability availability(Product product, {bool ignoreCart = false}) {
    final hasLimit = product.stock != null;
    final stock = product.stock;
    final inCart = ignoreCart
        ? 0
        : cart
                .where((item) => item.productId == product.id)
                .firstOrNull
                ?.qty ??
            0;
    if (!product.available) {
      return ProductAvailability(
        canSell: false,
        label: 'Nonaktif',
        status: 'unavailable',
        stock: stock,
      );
    }
    if (hasLimit && stock! <= 0) {
      return ProductAvailability(
        canSell: false,
        label: 'Habis',
        status: 'unavailable',
        stock: stock,
      );
    }
    if (hasLimit && inCart >= stock!) {
      return ProductAvailability(
        canSell: false,
        label: 'Batas stok tercapai',
        status: 'pending',
        stock: stock,
      );
    }
    if (hasLimit && stock! <= 3) {
      return ProductAvailability(
        canSell: true,
        label: 'Stok menipis',
        status: 'pending',
        stock: stock,
      );
    }
    return ProductAvailability(
      canSell: true,
      label: 'Tersedia',
      status: 'available',
      stock: stock,
    );
  }

  List<Product> get visibleProducts {
    return products.where((product) {
      if (!product.available) return false;
      final categoryMatch =
          category == 'semua' || product.category == category;
      final haystack = '${product.name} ${product.description}'.toLowerCase();
      final searchMatch = search.isEmpty || haystack.contains(search);
      return categoryMatch && searchMatch;
    }).toList();
  }

  List<Product> get menuProducts {
    return products.where((product) {
      final haystack = '${product.name} ${product.category}'.toLowerCase();
      final searchMatch = search.isEmpty || haystack.contains(search);
      if (!searchMatch) return false;
      final status = availability(product, ignoreCart: true).status;
      switch (menuFilter) {
        case 'available':
          return status == 'available';
        case 'low':
          return status == 'pending';
        case 'unavailable':
          return status == 'unavailable';
        default:
          return true;
      }
    }).toList();
  }

  Future<String?> saveProduct({
    String? id,
    required String name,
    required String categoryId,
    required int price,
    int? stock,
    required String description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Nama menu tidak boleh kosong.';
    final existing = id == null ? null : productById(id);
    final product = Product(
      id: existing?.id ?? uid('menu'),
      name: trimmed,
      category: categoryId,
      price: price < 0 ? 0 : price,
      stock: stock,
      description: description.trim(),
      available: existing?.available ?? true,
      emoji: existing?.emoji ??
          (categoryId == 'minuman'
              ? '🥤'
              : categoryId == 'topping'
                  ? '🍢'
                  : '🍜'),
    );
    if (existing != null) {
      final index = products.indexOf(existing);
      products[index] = product;
    } else {
      products.add(product);
    }
    notifyListeners();
    await _persist('products', products);
    _toast(existing != null
        ? 'Menu berhasil diperbarui.'
        : 'Menu baru berhasil ditambahkan.');
    return null;
  }

  Future<void> deleteProduct(String id) async {
    final product = productById(id);
    if (product == null) return;
    products = products.where((entry) => entry.id != id).toList();
    cart = cart.where((entry) => entry.productId != id).toList();
    notifyListeners();
    await _persist('products', products);
    await _saveCart();
    _toast('Menu dihapus dari katalog.');
  }

  Future<void> toggleProductAvailability(String id) async {
    final product = productById(id);
    if (product == null) return;
    product.available = !product.available;
    if (!product.available) {
      cart = cart.where((entry) => entry.productId != id).toList();
      await _saveCart();
    }
    notifyListeners();
    await _persist('products', products);
    _toast('${product.name} ${product.available ? 'diaktifkan' : 'dinonaktifkan'}.');
  }

  Future<String?> addCategory(String labelRaw, String emojiRaw) async {
    final label = labelRaw.trim();
    if (label.isEmpty) return 'Tulis nama kategori dulu.';
    final trimmed = label.length > 24 ? label.substring(0, 24) : label;
    if (categories.any(
      (entry) => entry.label.toLowerCase() == trimmed.toLowerCase(),
    )) {
      return 'Kategori dengan nama itu sudah ada.';
    }
    final emoji = normalizeEmoji(emojiRaw).isEmpty
        ? guessCategoryEmoji(trimmed)
        : normalizeEmoji(emojiRaw);
    categories.add(Category(
      id: _slugCategoryId(trimmed),
      label: trimmed,
      emoji: emoji,
    ));
    notifyListeners();
    await _persist('categories', categories);
    _toast('Kategori $emoji "$trimmed" ditambahkan.');
    return null;
  }

  String _slugCategoryId(String label) {
    final base = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    var id = base.isEmpty ? 'kategori' : base;
    var counter = 2;
    while (categories.any((entry) => entry.id == id)) {
      id = '$base-${counter++}';
    }
    return id;
  }

  Future<void> renameCategory(String id, String labelRaw) async {
    final entry = categoryById(id);
    if (entry == null) return;
    final label = labelRaw.trim();
    if (label.isEmpty || label == entry.label) return;
    entry.label = label.length > 24 ? label.substring(0, 24) : label;
    notifyListeners();
    await _persist('categories', categories);
    _toast('Kategori diganti menjadi "${entry.label}".');
  }

  Future<void> updateCategoryEmoji(String id, String emojiRaw) async {
    final entry = categoryById(id);
    if (entry == null) return;
    entry.emoji = normalizeEmoji(emojiRaw).isEmpty
        ? guessCategoryEmoji(entry.label)
        : normalizeEmoji(emojiRaw);
    notifyListeners();
    await _persist('categories', categories);
  }

  Future<void> deleteCategory(String id) async {
    final entry = categoryById(id);
    if (entry == null) return;
    final used = products.where((product) => product.category == id).length;
    if (used > 0) {
      _toast('Kategori "${entry.label}" dipakai ${formatNumber(used)} menu — '
          'pindahkan dulu sebelum menghapus.');
      return;
    }
    categories = categories.where((row) => row.id != id).toList();
    if (category == id) category = 'semua';
    notifyListeners();
    await _persist('categories', categories);
    _toast('Kategori "${entry.label}" dihapus.');
  }

  Future<void> saveBusiness({
    required String name,
    required String address,
    required String phone,
  }) async {
    settings.businessName =
        name.trim().isEmpty ? AppSettings().businessName : name.trim();
    settings.businessAddress = address.trim();
    settings.businessPhone = phone.trim();
    notifyListeners();
    await _persist('settings', settings);
    _toast('Identitas warung berhasil disimpan.');
  }

  Future<void> saveReceiptFooter(String footer, String rejection) async {
    settings.receiptFooter = footer.replaceAll('\r', '').trim();
    settings.onlineRejectionMessage =
        rejection.replaceAll('\r', '').trim().isEmpty
            ? AppSettings().onlineRejectionMessage
            : rejection.replaceAll('\r', '').trim();
    notifyListeners();
    await _persist('settings', settings);
    _toast('Tulisan struk dan penolakan berhasil disimpan.');
  }

  Future<void> setReceiptPaperSize(String size) async {
    settings.receiptPaperSize = size;
    notifyListeners();
    await _persist('settings', settings);
    _toast('Kertas cetak disetel ke $size.');
  }

  Future<void> setPrinter({
    required String model,
    required String address,
    required String name,
  }) async {
    settings.printerModel = model;
    settings.printerAddress = address;
    settings.printerDeviceName = name;
    notifyListeners();
    await _persist('settings', settings);
  }

  /// Mengembalikan pesan galat, atau `null` bila QRIS tersimpan.
  Future<String?> saveQris(String payloadRaw) async {
    final payload = payloadRaw.trim();
    if (payload.isEmpty) {
      settings.qrisStaticPayload = '';
      notifyListeners();
      await _persist('settings', settings);
      _toast('String QRIS statis dikosongkan.');
      return null;
    }
    final validation = QrisService.validate(payload);
    if (!validation.valid) {
      return 'QRIS tidak valid: ${validation.errors.join(' · ')}';
    }
    settings.qrisStaticPayload = payload;
    notifyListeners();
    await _persist('settings', settings);
    final merchant = QrisService.parse(payload).merchantName;
    _toast(merchant.isEmpty
        ? 'QRIS statis tersimpan.'
        : 'QRIS tersimpan — $merchant. Kasir siap membuat QRIS dinamis.');
    return null;
  }

  String get qrisPayload => settings.qrisStaticPayload.trim();

  /// QRIS dinamis untuk nominal tertentu, atau `null` bila belum diatur.
  String? dynamicQrisFor(int amount) {
    if (qrisPayload.isEmpty || amount <= 0) return null;
    try {
      return QrisService.convert(qrisPayload, amount: amount);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveApiBase(String value) async {
    apiBase = ApiClient.normalizeBase(value);
    api.configure(baseUrl: apiBase, token: api.token);
    await store.writeRaw(kStorageKeys['apiBase']!, apiBase);
    // Alamat berubah: daftar akun server harus dimuat ulang.
    serverUsers = null;
    userListStatus = '';
    notifyListeners();
    _toast(apiBase.isEmpty
        ? 'Alamat server dikosongkan — mode lokal.'
        : 'Alamat server disimpan.');
    if (apiBase.isNotEmpty && api.token.isNotEmpty) {
      unawaited(sync.syncNow());
    }
  }

  Future<void> setSyncEnabled(bool value) async {
    syncEnabled = value;
    await sync.setEnabled(value);
    notifyListeners();
  }

  Future<void> manualSync() async {
    if (!api.isConfigured) {
      _toast('Alamat server belum diatur — aplikasi berjalan mode lokal.');
      return;
    }
    _toast('Menyinkronkan…');
    final ok = await sync.syncNow();
    if (ok) {
      _toast('Sinkronisasi selesai.');
    } else if (syncStatus?.error.isNotEmpty ?? false) {
      _toast('Sinkronisasi gagal: ${syncStatus!.error}');
    } else {
      _toast('Belum ada koneksi — perubahan tetap diantre.');
    }
  }

  /* ======================================================================
     PENGGUNA LOKAL
     ====================================================================== */

  int activeOwnerCount([String? excludeUsername]) => localUsers
      .where((entry) =>
          entry.isOwner &&
          entry.active &&
          entry.username != (excludeUsername ?? ''))
      .length;

  Future<String?> addLocalUser({
    required String usernameRaw,
    required String nameRaw,
    required String role,
    required String password,
  }) async {
    final username = usernameRaw.trim().toLowerCase();
    final name = nameRaw.trim();
    if (!RegExp(r'^[a-z0-9._-]{3,60}$').hasMatch(username)) {
      return 'Nama pengguna: huruf kecil, angka, titik, garis bawah, strip (3-60 karakter).';
    }
    if (name.isEmpty) return 'Nama tampilan tidak boleh kosong.';
    if (password.length < 6) return 'Sandi minimal 6 karakter.';
    if (findLocalUser(username) != null) return 'Nama pengguna itu sudah dipakai.';
    localUsers.add(LocalUser(
      username: username,
      name: name,
      role: role == 'Pemilik' ? 'Pemilik' : 'Kasir',
      password: password,
    ));
    await _persistUsers();
    _toast('Pengguna ditambahkan.');
    return null;
  }

  Future<String?> updateLocalUser({
    required String username,
    required String name,
    required String role,
    String? password,
  }) async {
    final entry = findLocalUser(username);
    if (entry == null) return 'Akun tidak ditemukan.';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Nama tampilan tidak boleh kosong.';
    if (password != null && password.isNotEmpty && password.length < 6) {
      return 'Sandi minimal 6 karakter.';
    }
    if (entry.isOwner &&
        role != 'Pemilik' &&
        entry.active &&
        activeOwnerCount(entry.username) == 0) {
      return 'Harus ada minimal satu akun Pemilik yang aktif.';
    }
    entry.name = trimmed;
    entry.role = role == 'Pemilik' ? 'Pemilik' : 'Kasir';
    if (password != null && password.isNotEmpty) entry.password = password;
    await _persistUsers();
    final active = user;
    if (active != null && active.username == entry.username) {
      active.name = entry.name;
      active.role = entry.role;
      await store.writeJson(kStorageKeys['session']!, active.toJson());
      notifyListeners();
    }
    _toast('Akun diperbarui.');
    return null;
  }

  Future<String?> toggleLocalUser(String username) async {
    final entry = findLocalUser(username);
    if (entry == null) return 'Akun tidak ditemukan.';
    final activate = !entry.active;
    if (!activate && user?.username == entry.username) {
      return 'Tidak bisa menonaktifkan akun yang sedang dipakai.';
    }
    if (!activate && entry.isOwner && activeOwnerCount(entry.username) == 0) {
      return 'Harus ada minimal satu akun Pemilik yang aktif.';
    }
    entry.active = activate;
    await _persistUsers();
    _toast(activate ? 'Akun diaktifkan.' : 'Akun dinonaktifkan.');
    return null;
  }

  /* ======================================================================
     PENGGUNA SERVER
     ====================================================================== */

  Future<void> loadServerUsers() async {
    if (!accountsFromServer) {
      serverUsers = null;
      userListStatus = '';
      notifyListeners();
      return;
    }
    try {
      final body = await api.get('/api/users');
      final raw = body['users'];
      serverUsers = raw is List
          ? raw
              .whereType<Map>()
              .map((row) => ServerUser.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : <ServerUser>[];
      userListStatus = '${serverUsers!.length} akun dimuat dari server.';
    } on ApiException catch (error) {
      serverUsers = null;
      userListStatus =
          'Gagal memuat daftar akun dari server: ${error.message}';
    } catch (error) {
      serverUsers = null;
      userListStatus = 'Gagal memuat daftar akun dari server: $error';
    }
    notifyListeners();
  }

  Future<String?> createUser({
    required String usernameRaw,
    required String nameRaw,
    required String role,
    required String password,
  }) async {
    final username = usernameRaw.trim().toLowerCase();
    final name = nameRaw.trim();
    if (!RegExp(r'^[a-z0-9._-]{3,60}$').hasMatch(username)) {
      return 'Nama pengguna: huruf kecil, angka, titik, garis bawah, strip (3-60 karakter).';
    }
    if (name.isEmpty) return 'Nama tampilan tidak boleh kosong.';
    if (password.length < 6) return 'Sandi minimal 6 karakter.';
    if (!accountsFromServer) {
      return addLocalUser(
        usernameRaw: username,
        nameRaw: name,
        role: role,
        password: password,
      );
    }
    try {
      await api.post('/api/users', {
        'username': username,
        'displayName': name,
        'role': role == 'Pemilik' ? 'Pemilik' : 'Kasir',
        'password': password,
      });
      await loadServerUsers();
      _toast('Pengguna ditambahkan.');
      return null;
    } on ApiException catch (error) {
      return 'Gagal menambah pengguna: ${error.message}';
    }
  }

  Future<String?> updateServerUser({
    required String id,
    required String name,
    required String role,
    String? password,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Nama tampilan tidak boleh kosong.';
    if (password != null && password.isNotEmpty && password.length < 6) {
      return 'Sandi minimal 6 karakter.';
    }
    final body = <String, dynamic>{
      'displayName': trimmed,
      'role': role == 'Pemilik' ? 'Pemilik' : 'Kasir',
    };
    if (password != null && password.isNotEmpty) body['password'] = password;
    try {
      await api.put('/api/users/${Uri.encodeComponent(id)}', body);
      await loadServerUsers();
      final updated =
          serverUsers?.where((entry) => entry.id == id).firstOrNull;
      final active = user;
      if (updated != null && active != null && active.username == updated.username) {
        active.name = updated.name;
        active.role = updated.role;
        await store.writeJson(kStorageKeys['session']!, active.toJson());
        notifyListeners();
      }
      _toast('Akun diperbarui.');
      return null;
    } on ApiException catch (error) {
      return 'Gagal menyimpan: ${error.message}';
    }
  }

  Future<String?> toggleServerUser(ServerUser entry) async {
    final activate = !entry.active;
    if (!activate && user?.username == entry.username) {
      return 'Tidak bisa menonaktifkan akun yang sedang dipakai.';
    }
    try {
      await api.put('/api/users/${Uri.encodeComponent(entry.id)}', {
        'active': activate,
      });
      await loadServerUsers();
      _toast(activate ? 'Akun diaktifkan.' : 'Akun dinonaktifkan.');
      return null;
    } on ApiException catch (error) {
      return 'Gagal: ${error.message}';
    }
  }

  Future<void> _persistUsers() async {    await store.writeJson(
      kStorageKeys['users']!,
      localUsers.map((entry) => entry.toJson()).toList(),
    );
    notifyListeners();
  }

  /* ======================================================================
     KERANJANG
     ====================================================================== */

  CartItem? cartItemById(String productId) =>
      cart.where((item) => item.productId == productId).firstOrNull;

  bool cartItemMissing(CartItem item) => productById(item.productId) == null;

  int cartItemPrice(CartItem item) {
    final product = productById(item.productId);
    return product != null ? unitPrice(product) : item.price;
  }

  String cartItemName(CartItem item) {
    final product = productById(item.productId);
    return product != null ? product.name : (item.name.isEmpty ? 'Menu tidak ada' : item.name);
  }

  String cartItemEmoji(CartItem item) {
    final product = productById(item.productId);
    return (product != null && product.emoji.isNotEmpty)
        ? product.emoji
        : (item.emoji.isEmpty ? '🍽️' : item.emoji);
  }

  CartTotals get cartTotals {
    final subtotal =
        cart.fold(0, (sum, item) => sum + cartItemPrice(item) * item.qty);
    final discount = cartDiscount.clamp(0, subtotal);
    return CartTotals(
      subtotal: subtotal,
      discount: discount,
      total: subtotal - discount,
    );
  }

  Future<bool> addToCart(String productId) async {
    final product = productById(productId);
    if (product == null || !availability(product).canSell) {
      _toast('Menu ini sedang tidak tersedia.');
      return false;
    }
    final existing = cartItemById(productId);
    if (existing != null) {
      existing.qty += 1;
      existing.name = product.name;
      existing.price = unitPrice(product);
      existing.emoji = product.emoji;
    } else {
      cart.add(CartItem(
        productId: productId,
        qty: 1,
        name: product.name,
        price: unitPrice(product),
        emoji: product.emoji,
      ));
    }
    notifyListeners();
    await _saveCart();
    return true;
  }

  Future<void> changeCartQuantity(String productId, int change) async {
    final item = cartItemById(productId);
    if (item == null) return;
    final product = productById(productId);
    if (change > 0 && product == null) {
      _toast('Menu ini sudah tidak ada di daftar menu — kurangi atau hapus '
          'dari keranjang.', 6000);
      return;
    }
    if (change > 0 && product != null && !product.available) {
      _toast('${product.name} sedang dinonaktifkan.');
      return;
    }
    if (change > 0 && product?.stock != null && item.qty + change > product!.stock!) {
      _toast('Stok ${product.name} hanya ${product.stock}.');
      return;
    }
    item.qty += change;
    if (item.qty <= 0) {
      cart = cart.where((row) => row.productId != productId).toList();
    }
    notifyListeners();
    await _saveCart();
  }

  Future<void> removeCartItem(String productId) async {
    cart = cart.where((item) => item.productId != productId).toList();
    notifyListeners();
    await _saveCart();
  }

  Future<void> clearCart() async {
    cart = [];
    cartDiscount = 0;
    cartNote = '';
    notifyListeners();
    await _saveCart();
  }

  Future<void> setCartDiscount(int value) async {
    cartDiscount = value < 0 ? 0 : value;
    notifyListeners();
    await _saveCart();
  }

  Future<void> setTableNumber(String value) async {
    tableNumber = value;
    notifyListeners();
    await _saveCart();
  }

  Future<void> setCartNote(String value) async {
    cartNote = value.length > 120 ? value.substring(0, 120) : value;
    notifyListeners();
    await _saveCart();
  }

  Future<void> setOrderType(String value) async {
    orderType = value == 'takeaway' ? 'takeaway' : 'dine-in';
    notifyListeners();
    await _saveCart();
  }

  Future<void> setCartItemNote(String productId, String note) async {
    final item = cartItemById(productId);
    if (item == null) return;
    item.note = note.length > 120 ? note.substring(0, 120) : note;
    await _saveCart();
  }

  void toggleCartNote(String productId) {
    cartNoteOpenId = cartNoteOpenId == productId ? null : productId;
    notifyListeners();
  }

  Future<void> switchCartTab(String tab) async {
    cartTab = _normalizeCartTab(tab);
    await store.writeRaw(kStorageKeys['cartTab']!, cartTab);
    notifyListeners();
  }

  String _normalizeCartTab(String value) =>
      ['cart', 'pending', 'online'].contains(value) ? value : 'cart';

  /* ======================================================================
     PEMBAYARAN & PESANAN
     ====================================================================== */

  Future<Order?> completePayment({
    required String payment,
    int cashReceived = 0,
  }) async {
    if (cart.isEmpty) return null;
    final unavailable = cart.where((item) {
      final product = productById(item.productId);
      if (product == null || !product.available) return true;
      return product.stock != null && item.qty > product.stock!;
    }).toList();
    if (unavailable.isNotEmpty) {
      final orphans =
          cart.where(cartItemMissing).map(cartItemName).toList();
      _toast(
        orphans.isNotEmpty
            ? '${orphans.join(', ')} sudah tidak ada di daftar menu — hapus '
                'dari keranjang sebelum membayar.'
            : 'Ada menu yang tidak tersedia atau melebihi stok. Perbarui '
                'keranjang sebelum membayar.',
        6000,
      );
      notifyListeners();
      return null;
    }

    final totals = cartTotals;
    final received = payment == 'cash' ? cashReceived : totals.total;
    if (payment == 'cash' && received < totals.total) {
      _toast('Uang diterima kurang dari total.');
      return null;
    }

    final now = DateTime.now();
    final order = Order(
      id: newOrderId(now),
      clientTxnId: uuidV4(),
      createdAt: now.toUtc().toIso8601String(),
      items: cart.map((item) {
        final unit = cartItemPrice(item);
        return OrderItem(
          productId: item.productId,
          name: cartItemName(item),
          price: unit,
          qty: item.qty,
          total: unit * item.qty,
          note: item.note.trim(),
        );
      }).toList(),
      orderType: orderType,
      tableNumber: orderType == 'dine-in' ? tableNumber.trim() : '',
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      taxRate: settings.taxRate,
      taxIncluded: true,
      payment: payment,
      paidAmount: received,
      changeAmount: received - totals.total < 0 ? 0 : received - totals.total,
      status: 'paid',
      cashier: user?.name ?? 'kasir',
      note: cartNote.trim(),
    );

    orders.add(order);
    _deductStock(order);
    currentOrder = order;
    cart = [];
    cartDiscount = 0;
    tableNumber = '';
    cartNote = '';
    notifyListeners();

    await _persistAll();
    await _saveCart();
    _noteOrderSaved();
    return order;
  }

  void _deductStock(Order order) {
    for (final item in order.items) {
      final product = productById(item.productId);
      if (product == null || product.stock == null) continue;
      product.stock = (product.stock! - item.qty).clamp(0, 1 << 30);
    }
  }

  Future<bool> holdOrder() async {
    if (cart.isEmpty) return false;
    final items = <OrderItem>[];
    for (final item in cart) {
      final product = productById(item.productId);
      if (product == null) continue;
      final unit = unitPrice(product);
      items.add(OrderItem(
        productId: product.id,
        name: product.name,
        price: unit,
        qty: item.qty,
        total: unit * item.qty,
        note: item.note.trim(),
      ));
    }
    if (items.isEmpty) {
      _toast('Semua menu di keranjang sudah tidak ada. Kosongkan keranjang dulu.',
          6000);
      return false;
    }
    final totals = cartTotals;
    final now = DateTime.now();
    final pending = PendingOrder(
      id: newHoldId(now),
      createdAt: now.toUtc().toIso8601String(),
      orderType: orderType,
      tableNumber: orderType == 'dine-in' ? tableNumber.trim() : '',
      items: items,
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      status: 'pending',
      payment: null,
      cashier: user?.name ?? 'kasir',
      note: cartNote.trim(),
    );
    pendingOrders.add(pending);
    cart = [];
    cartDiscount = 0;
    tableNumber = '';
    cartNote = '';
    notifyListeners();
    await _persist('pending', pendingOrders);
    await _saveCart();
    _toast('Pesanan ${pending.id} disimpan (belum dibayar). Lanjutkan lewat tab '
        '"Bayar nanti".');
    return true;
  }

  Future<bool> resumePendingOrder(String id) async {
    final pending = pendingOrders.where((entry) => entry.id == id).firstOrNull;
    if (pending == null) return false;
    final items = pending.items
        .where((item) => productById(item.productId) != null)
        .toList();
    final missing = pending.items.length - items.length;
    if (items.isEmpty) {
      _toast('Pesanan ${pending.id} memakai menu yang sudah tidak ada. '
          'Pesanan tetap tersimpan — kembalikan menunya atau batalkan pesanan.',
          7000);
      return false;
    }
    _removePending(id);
    orderType = pending.orderType;
    cart = items
        .map((item) => CartItem(
              productId: item.productId,
              qty: item.qty,
              name: item.name,
              price: item.price,
              note: item.note.trim(),
            ))
        .toList();
    tableNumber = pending.tableNumber;
    cartDiscount = pending.discount;
    cartNote = pending.note;
    notifyListeners();
    await _persist('pending', pendingOrders);
    await _saveCart();
    _toast(
      missing > 0
          ? 'Pesanan ${pending.id} dimuat. $missing menu sudah tidak ada di '
              'daftar menu dan tidak ikut dimuat.'
          : 'Pesanan ${pending.id} dimuat kembali untuk pembayaran.',
      missing > 0 ? 6500 : 3200,
    );
    return true;
  }

  Future<void> finishPendingOrder(String id) async {
    final pending = pendingOrders.where((entry) => entry.id == id).firstOrNull;
    if (pending == null) return;
    _removePending(id);
    notifyListeners();
    await _persist('pending', pendingOrders);
    _toast('Pesanan ${pending.id} selesai dibuat.');
  }

  Future<void> cancelPendingOrder(String id) async {
    final pending = pendingOrders.where((entry) => entry.id == id).firstOrNull;
    if (pending == null) return;
    _removePending(id);
    notifyListeners();
    await _persist('pending', pendingOrders);
    _toast('Pesanan dibatalkan.');
  }

  void _removePending(String id) {
    final index = pendingOrders.indexWhere((entry) => entry.id == id);
    if (index >= 0) pendingOrders.removeAt(index);
  }

  /* ======================================================================
     PESANAN ONLINE
     ====================================================================== */

  List<OrderItem> resolveOnlineItems(OnlineOrder order) {
    final resolved = <OrderItem>[];
    for (final entry in order.items) {
      final product = productById(entry.productId);
      if (product == null) continue;
      final qty = entry.qty < 1 ? 1 : entry.qty;
      final price = entry.price ?? product.price;
      resolved.add(OrderItem(
        productId: product.id,
        name: product.name,
        price: price,
        qty: qty,
        total: price * qty,
        note: entry.note,
      ));
    }
    return resolved;
  }

  int onlineSubtotal(OnlineOrder order) =>
      resolveOnlineItems(order).fold(0, (sum, item) => sum + item.total);

  int onlineTotal(OnlineOrder order) {
    if (order.totalOverride != null && order.totalOverride! > 0) {
      return order.totalOverride!;
    }
    final subtotal = onlineSubtotal(order);
    final discount = order.discount.clamp(0, subtotal);
    return subtotal - discount;
  }

  List<OnlineOrder> get visibleOnlineOrders => onlineOrders
      .where((order) =>
          order.status == onlineStatusFilter &&
          (onlinePlatformFilter == 'all' ||
              order.source == onlinePlatformFilter))
      .toList();

  Map<String, int> get onlineStatusCounts {
    final counts = <String, int>{'baru': 0, 'dibuat': 0, 'siap': 0};
    for (final order in onlineOrders) {
      counts[order.status] = (counts[order.status] ?? 0) + 1;
    }
    return counts;
  }

  void setOnlineStatusFilter(String value) {
    if (!['baru', 'dibuat', 'siap'].contains(value)) return;
    onlineStatusFilter = value;
    notifyListeners();
  }

  void setOnlinePlatformFilter(String value) {
    onlinePlatformFilter = value.isEmpty ? 'all' : value;
    notifyListeners();
  }

  String _makePickupCode(OnlineOrder order) {
    // GoFood/Grab memakai 4 digit seperti aslinya; platform lain memakai
    // nomor pesanan dari aplikasi (fallback "0000"), sama seperti web.
    if (order.source == 'gofood' || order.source == 'grab') {
      return pickupCode();
    }
    return order.code.isEmpty ? '0000' : order.code;
  }

  bool _ensurePickupCodes() {
    var changed = false;
    for (final order in onlineOrders) {
      if (order.status == 'siap' && order.pickupCode.isEmpty) {
        order.pickupCode = _makePickupCode(order);
        changed = true;
      }
    }
    return changed;
  }

  Future<void> advanceOnlineOrder(String id) async {
    final order = onlineOrders.where((entry) => entry.id == id).firstOrNull;
    if (order == null) return;
    if (resolveOnlineItems(order).isEmpty) {
      _toast('Item pesanan tidak ditemukan di menu. Perbarui menu dulu.');
      return;
    }
    const next = {'baru': 'dibuat', 'dibuat': 'siap', 'siap': 'selesai'};
    final target = next[order.status];
    if (target == null) return;

    if (target == 'selesai') {
      _removeOnline(id);
      final completed = _buildCompletedOnlineOrder(order);
      orders.add(completed);
      _deductStock(completed);
      notifyListeners();
      await _persist('online', onlineOrders);
      await _persistAll();
      _noteOrderSaved();
      _toast('Pesanan ${order.code} selesai & tercatat di laporan.');
      return;
    }

    order.status = target;
    if (target == 'siap') {
      order.pickupCode = _makePickupCode(order);
    }
    notifyListeners();
    await _persist('online', onlineOrders);
    _toast('Pesanan ${order.code} '
        '${target == 'dibuat' ? 'diterima' : 'siap diambil'}.');
  }

  Order _buildCompletedOnlineOrder(OnlineOrder order) {
    final items = resolveOnlineItems(order);
    final subtotal = items.fold(0, (sum, item) => sum + item.total);
    return Order(
      id: 'ONL-${order.code.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString().substring(9) : order.code}',
      clientTxnId: uuidV4(),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      items: items,
      orderType: 'online',
      tableNumber: '',
      subtotal: subtotal,
      discount: 0,
      total: subtotal,
      taxRate: settings.taxRate,
      taxIncluded: true,
      payment: kOnlinePlatforms.containsKey(order.source) ? order.source : 'other',
      paidAmount: subtotal,
      changeAmount: 0,
      status: 'paid',
      cashier: user?.name ?? 'kasir',
      onlineCode: order.code,
      onlineCustomer: order.customer,
    );
  }

  Future<void> rejectOnlineOrder(String id, String reasonRaw) async {
    final order = onlineOrders.where((entry) => entry.id == id).firstOrNull;
    if (order == null) return;
    final wasNew = order.status == 'baru';
    _removeOnline(id);
    notifyListeners();
    await _persist('online', onlineOrders);
    _toast(wasNew
        ? 'Pesanan ${order.code} ditolak.'
        : 'Pesanan ${order.code} dibatalkan.');
  }

  void _removeOnline(String id) {
    final index = onlineOrders.indexWhere((entry) => entry.id == id);
    if (index >= 0) onlineOrders.removeAt(index);
  }

  Future<void> deleteOrder(String id) async {
    orders = orders.where((entry) => entry.id != id).toList();
    notifyListeners();
    await _persist('orders', orders);
    _toast('Transaksi dihapus dari laporan. Stok tidak dikembalikan.');
  }

  Future<void> clearHistory() async {
    orders = [];
    pendingOrders = [];
    onlineOrders = [];
    notifyListeners();
    await _persistAll();
    _toast('Riwayat pembelian dibersihkan.');
  }

  /* ======================================================================
     LAPORAN
     ====================================================================== */

  List<Order> ordersForDate(String key) =>
      orders.where((order) => orderDateKey(order.createdAt) == key).toList();

  List<Order> filteredOrders(String from, String to) => orders.where((order) {
        final key = orderDateKey(order.createdAt);
        final statusOk = order.status.isEmpty || order.status == 'paid';
        return statusOk && key.isNotEmpty && key.compareTo(from) >= 0 && key.compareTo(to) <= 0;
      }).toList();

  ReportSummary reportSummary(String from, String to) =>
      ReportSummary(orders: filteredOrders(from, to), from: from, to: to);

  Future<void> exportReport({
    required String from,
    required String to,
    required String kindLabel,
  }) async {
    final summary = reportSummary(from, to);
    final isToday = from == to;
    final label = kindLabel.isNotEmpty
        ? kindLabel
        : (isToday ? 'Harian' : 'Rentang');
    final title = label == 'Mingguan'
        ? 'LAPORAN PENJUALAN MINGGUAN'
        : label == 'Harian'
            ? 'LAPORAN PENJUALAN HARIAN'
            : 'LAPORAN PENJUALAN';
    final slug = label == 'Mingguan'
        ? 'mingguan'
        : label == 'Harian'
            ? 'harian'
            : 'rentang';
    final filename = 'mpj-laporan-$slug-$from-$to.xlsx';
    try {
      final bytes = reports.buildXlsx(
        summary: summary,
        businessName: settings.businessName,
        title: title,
        kindLabel: label,
      );
      await reports.shareXlsx(bytes: bytes, filename: filename);
      _toast('Laporan Excel dibagikan: $filename');
    } catch (error) {
      _toast('Laporan Excel gagal dibuat ($error).', 6000);
    }
  }

  /* ======================================================================
     CETAK
     ====================================================================== */

  Future<void> printReceipt(Order order, {int copies = 1}) async {
    final address = settings.printerAddress;
    if (address.isEmpty) {
      await shareReceiptPdf(order);
      _toast('Printer belum diatur — struk dibagikan sebagai PDF.');
      return;
    }
    try {
      final lines = ReceiptBuilder.forOrder(order, settings);
      await printer.printEscPos(
        address: address,
        lines: lines,
        paperSize: settings.receiptPaperSize,
        copies: copies,
      );
      _toast('Struk dikirim ke printer.');
    } catch (error) {
      _toast('Gagal mencetak: $error');
    }
  }

  Future<void> shareReceiptPdf(Order order) async {
    try {
      final lines = ReceiptBuilder.forOrder(order, settings);
      await printer.sharePdf(
        lines: lines,
        filename: 'struk-${order.id}.pdf',
        title: 'Struk ${order.id}',
        paperSize: settings.receiptPaperSize,
      );
    } catch (error) {
      _toast('Gagal membuat PDF: $error');
    }
  }

  Future<void> printOnlineTicket(OnlineOrder order) async {
    final address = settings.printerAddress;
    final items = resolveOnlineItems(order);
    final subtotal = items.fold(0, (sum, item) => sum + item.total);
    final lines = ReceiptBuilder.forOnlineTicket(
      order,
      settings,
      items: items,
      subtotal: subtotal,
      total: onlineTotal(order),
    );
    if (address.isEmpty) {
      await printer.sharePdf(
        lines: lines,
        filename: 'nota-${order.code.isEmpty ? order.id : order.code}.pdf',
        title: 'Nota ${order.code}',
        paperSize: settings.receiptPaperSize,
      );
      _toast('Printer belum diatur — nota dibagikan sebagai PDF.');
      return;
    }
    try {
      await printer.printEscPos(
        address: address,
        lines: lines,
        paperSize: settings.receiptPaperSize,
      );
      _toast('Nota dikirim ke printer.');
    } catch (error) {
      _toast('Gagal mencetak: $error');
    }
  }

  /* ======================================================================
     UTIL
     ====================================================================== */

  void _toast(String message, [int duration = 3200]) {
    onToast?.call(message);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _midnightTimer?.cancel();
    unawaited(sync.stop());
    super.dispose();
  }
}

class ProductAvailability {
  const ProductAvailability({
    required this.canSell,
    required this.label,
    required this.status,
    this.stock,
  });

  final bool canSell;
  final String label;
  final String status;
  final int? stock;
}

String normalizeEmoji(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  final runes = text.runes.where((rune) => rune > 31).take(4).toList();
  return String.fromCharCodes(runes);
}

String guessCategoryEmoji(String label) {
  final text = label.toLowerCase();
  if (RegExp(r'minum|juice|es |teh|kop|susu|drink|air').hasMatch(text)) {
    return '🥤';
  }
  if (RegExp(r'topping|pelengkap|tambahan|extra').hasMatch(text)) return '🥟';
  if (RegExp(r'snack|camilan|keripik|cemilan').hasMatch(text)) return '🍟';
  if (RegExp(r'nasi|rice').hasMatch(text)) return '🍚';
  if (RegExp(r'sup|sop').hasMatch(text)) return '🍲';
  if (RegExp(r'roti|bread|kue|cake|pastry').hasMatch(text)) return '🍞';
  if (RegExp(r'sayur|vegetable|salad').hasMatch(text)) return '🥗';
  if (RegExp(r'bubur|porridge').hasMatch(text)) return '🥣';
  return '🍽️';
}
