import '../models/models.dart';

/// Versi katalog bawaan — naikkan bila daftar menu/kategori bawaan diganti.
const int kCatalogVersion = 2;

/// Hanya satu titik pemulihan lokal yang disimpan.
const int kSnapshotLimit = 1;

/// Cadangan otomatis tiap 10 transaksi.
const int kSnapshotEveryOrders = 10;

const String kCatMenuPangsit = 'mie-pangsit-jakarta';
const String kCatMieKering = 'mie-kering';
const String kCatSpecial = 'special-menu';

const Map<String, String> kStorageKeys = {
  'products': 'mpj_pos_products',
  'orders': 'mpj_pos_orders',
  'settings': 'mpj_pos_settings',
  'session': 'mpj_pos_session',
  'theme': 'mpj_pos_theme',
  'pending': 'mpj_pos_pending',
  'online': 'mpj_pos_online',
  'categories': 'mpj_pos_categories',
  'snapshots': 'mpj_pos_snapshots',
  'lastExport': 'mpj_pos_last_export',
  'catalog': 'mpj_pos_catalog_version',
  'cartTab': 'mpj_pos_cart_tab',
  'cartData': 'mpj_pos_cart_data',
  'users': 'mpj_pos_users',
  'apiBase': 'mpj_api_base',
  'apiToken': 'mpj_api_token',
  'syncCursorSince': 'mpj_sync_cursor_since',
  'syncCursorId': 'mpj_sync_cursor_id',
  'syncDeviceId': 'mpj_sync_device_id',
  'syncEnabled': 'mpj_sync_enabled',
  'syncLastAt': 'mpj_sync_last_at',
};

const List<Map<String, dynamic>> kDefaultProducts = [
  // Mie Pangsit Jakarta
  {'id': 'pangsit-original', 'name': 'Mie Pangsit Original', 'category': kCatMenuPangsit, 'price': 20000, 'description': 'Pangsit dalam dibungkus mie dengan kuah bening gurih.', 'stock': null, 'available': true, 'emoji': '🍜'},
  {'id': 'pangsit-pentol', 'name': 'Mie Pangsit Pentol', 'category': kCatMenuPangsit, 'price': 25000, 'description': 'Pangsit dalam isi pentol, level 1 sampai 3.', 'stock': null, 'available': true, 'emoji': '🥟'},
  {'id': 'pangsit-ceker', 'name': 'Mie Pangsit Ceker', 'category': kCatMenuPangsit, 'price': 25000, 'description': 'Pangsit dalam isi ceker yang gurih.', 'stock': null, 'available': true, 'emoji': '🍗'},
  {'id': 'pangsit-telur', 'name': 'Mie Pangsit Telur Puyuh', 'category': kCatMenuPangsit, 'price': 25000, 'description': 'Pangsit dalam isi telur puyuh.', 'stock': null, 'available': true, 'emoji': '🥚'},
  {'id': 'paket-komplit', 'name': 'Mie Pangsit Komplit', 'category': kCatMenuPangsit, 'price': 30000, 'description': 'Isi lengkap: Pentol, Telur Puyuh, dan Ceker.', 'stock': null, 'available': true, 'emoji': '🎯'},
  // Mie Kering
  {'id': 'mie-kering', 'name': 'Mie Kering (Level 1, 2, 3)', 'category': kCatMieKering, 'price': 20000, 'description': 'Mie kering dengan level kepedasan 1, 2, atau 3.', 'stock': null, 'available': true, 'emoji': '🥢'},
  {'id': 'santuy', 'name': 'Mie Santuy', 'category': kCatMieKering, 'price': 15000, 'description': 'Mie rebus santuy khas warung.', 'stock': null, 'available': true, 'emoji': '🍜'},
  {'id': 'guobiyos', 'name': 'Mie Guobiyos', 'category': kCatMieKering, 'price': 15000, 'description': 'Mie rebus dengan bumbu dan sambal khas.', 'stock': null, 'available': true, 'emoji': '🍲'},
  // Special menu
  {'id': 'wonton-siomay-goreng', 'name': 'Wonton Siomay Goreng', 'category': kCatSpecial, 'price': 15000, 'description': 'Wonton dan siomay digoreng sampai garing.', 'stock': null, 'available': true, 'emoji': '🥠'},
  {'id': 'wonton-siomay', 'name': 'Wonton Siomay', 'category': kCatSpecial, 'price': 15000, 'description': 'Wonton dan siomay rebus dengan saus.', 'stock': null, 'available': true, 'emoji': '🥟'},
  {'id': 'bakso', 'name': 'Bakso', 'category': kCatSpecial, 'price': 20000, 'description': 'Bakso dalam mangkuk dengan kuah kaldu.', 'stock': null, 'available': true, 'emoji': '🍲'},
  {'id': 'mie-gurih', 'name': 'Mie Gurih', 'category': kCatSpecial, 'price': 20000, 'description': 'Mie rebus gurih dengan topping.', 'stock': null, 'available': true, 'emoji': '🍜'},
  // Topping
  {'id': 'telur-puyuh-topping', 'name': 'Telur Puyuh', 'category': 'topping', 'price': 6000, 'description': 'Telur puyuh rebus.', 'stock': null, 'available': true, 'emoji': '🥚'},
  {'id': 'siomay-rebus', 'name': 'Siomay Rebus', 'category': 'topping', 'price': 6000, 'description': 'Siomay rebus dengan saus.', 'stock': null, 'available': true, 'emoji': '🥟'},
  {'id': 'pentol', 'name': 'Pentol', 'category': 'topping', 'price': 6000, 'description': 'Pentol bakso rebus.', 'stock': null, 'available': true, 'emoji': '🍢'},
  {'id': 'ceker', 'name': 'Ceker', 'category': 'topping', 'price': 6000, 'description': 'Ceker ayam rebus.', 'stock': null, 'available': true, 'emoji': '🍗'},
  // Minuman
  {'id': 'teh-tawar', 'name': 'Teh Tawar', 'category': 'minuman', 'price': 4000, 'description': 'Teh tawar tanpa gula.', 'stock': null, 'available': true, 'emoji': '🍵'},
  {'id': 'teh-es-panas', 'name': 'Teh Es/Panas', 'category': 'minuman', 'price': 6000, 'description': 'Teh es dengan gula atau teh panas.', 'stock': null, 'available': true, 'emoji': '🧋'},
  {'id': 'air-mineral', 'name': 'Air Mineral', 'category': 'minuman', 'price': 6000, 'description': 'Air mineral dingin.', 'stock': null, 'available': true, 'emoji': '💧'},
  {'id': 'kopi-hitam', 'name': 'Kopi Hitam', 'category': 'minuman', 'price': 8000, 'description': 'Kopi hitam tanpa gula.', 'stock': null, 'available': true, 'emoji': '☕'},
  {'id': 'jeruk', 'name': 'Jeruk Es/Panas', 'category': 'minuman', 'price': 8000, 'description': 'Jus jeruk es atau hangat.', 'stock': null, 'available': true, 'emoji': '🍊'},
  {'id': 'cappuccino', 'name': 'Cappuccino Es/Panas', 'category': 'minuman', 'price': 8000, 'description': 'Cappuccino es atau hangat.', 'stock': null, 'available': true, 'emoji': '☕'},
  {'id': 'coklat', 'name': 'Cokelat Es/Panas', 'category': 'minuman', 'price': 10000, 'description': 'Cokelat es atau hangat.', 'stock': null, 'available': true, 'emoji': '🍫'},
  {'id': 'lemon-tea', 'name': 'Lemon Tea Es/Panas', 'category': 'minuman', 'price': 12000, 'description': 'Teh lemon es atau hangat.', 'stock': null, 'available': true, 'emoji': '🍋'},
  {'id': 'es-kelapa', 'name': 'Es Kelapa', 'category': 'minuman', 'price': 15000, 'description': 'Es kelapa muda segar.', 'stock': null, 'available': true, 'emoji': '🥥'},
];

const List<Map<String, dynamic>> kDefaultCategories = [
  {'id': kCatMenuPangsit, 'label': 'Mie Pangsit Jakarta', 'emoji': '🍜'},
  {'id': kCatMieKering, 'label': 'Mie Kering', 'emoji': '🥢'},
  {'id': kCatSpecial, 'label': 'Special menu', 'emoji': '🍢'},
  {'id': 'topping', 'label': 'Topping', 'emoji': '🥟'},
  {'id': 'minuman', 'label': 'Minuman', 'emoji': '🥤'},
];

const List<String> kCategoryEmojiChoices = [
  '🍜', '🍲', '🍚', '🍝', '🍛', '🍱', '🥣', '🥢', '🍥',
  '🥟', '🥠', '🍢', '🍡', '🍗', '🍖', '🥘', '🍳',
  '🥗', '🥬', '🥒', '🍅', '🌽', '🍠', '🥔', '🍆',
  '🥤', '🧋', '☕', '🍵', '🧃', '🍶', '🥛', '🍹', '🥥', '🍋', '🍊', '💧',
  '🍰', '🍮', '🍪', '🍫', '🍭', '🍨', '🍦',
  '🍽️', '🍟', '⭐', '🔥', '✨', '🎯', '🌶️',
];

const String kEmojiAutoIcon = '🔄';

const List<Map<String, dynamic>> kDefaultLocalUsers = [
  {'username': 'pemilik', 'name': 'Pemilik', 'role': 'Pemilik', 'active': true, 'password': '1234'},
  {'username': 'kasir', 'name': 'Kasir', 'role': 'Kasir', 'active': true, 'password': '1234'},
];

const Map<String, String> kOnlinePlatforms = {
  'gofood': 'GoFood',
  'shopee': 'ShopeeFood',
  'grab': 'GrabFood',
  'other': 'Online',
};

const Map<String, String> kOnlineStatus = {
  'baru': 'Baru',
  'dibuat': 'Dibuat',
  'siap': 'Siap diambil',
};

const Map<String, String> kPaymentLabels = {
  'cash': 'Tunai',
  'qris': 'QRIS',
  'transfer': 'Transfer',
  'card': 'Kartu',
  'gofood': 'GoFood',
  'shopee': 'ShopeeFood',
  'grab': 'GrabFood',
  'maxim': 'Maxim',
  'other': 'Online',
  'online': 'Online',
};

const Map<String, String> kReceiptPaymentLabels = {
  'cash': 'Tunai',
  'qris': 'QRIS',
  'transfer': 'Transfer',
  'card': 'Kartu',
};

const List<Map<String, dynamic>> kDummyOnlineOrders = [
  {
    'id': 'ONL-GF-2174',
    'source': 'gofood',
    'code': 'GF-2174',
    'customer': 'Dina',
    'note': 'Pedas level 2',
    'status': 'baru',
    'minutesAgo': 12,
    'items': [
      {'productId': 'pangsit-original', 'qty': 2},
      {'productId': 'teh-es-panas', 'qty': 2},
    ],
  },
  {
    'id': 'ONL-GR-9041',
    'source': 'grab',
    'code': 'GR-9041',
    'customer': 'Rizky',
    'note': '',
    'status': 'dibuat',
    'minutesAgo': 8,
    'items': [
      {'productId': 'bakso', 'qty': 1},
      {'productId': 'paket-komplit', 'qty': 1},
      {'productId': 'jeruk', 'qty': 1},
    ],
  },
  {
    'id': 'ONL-SP-5512',
    'source': 'shopee',
    'code': 'SP-5512',
    'customer': 'Maya',
    'note': 'Saus sambal dipisah',
    'status': 'siap',
    'minutesAgo': 4,
    'items': [
      {'productId': 'mie-kering', 'qty': 2},
      {'productId': 'lemon-tea', 'qty': 1},
    ],
  },
];

List<Product> defaultProducts() =>
    kDefaultProducts.map((json) => Product.fromJson(Map<String, dynamic>.from(json))).toList();

List<Category> defaultCategories() =>
    kDefaultCategories.map((json) => Category.fromJson(Map<String, dynamic>.from(json))).toList();

List<LocalUser> defaultLocalUsers() =>
    kDefaultLocalUsers.map((json) => LocalUser.fromJson(Map<String, dynamic>.from(json))).toList();

AppSettings defaultSettings() => AppSettings();

/// Pesanan online contoh dipakai saat perangkat baru pertama kali dibuka.
List<OnlineOrder> dummyOnlineOrders() {
  final now = DateTime.now();
  return kDummyOnlineOrders.map((json) {
    final copy = Map<String, dynamic>.from(json);
    copy['createdAt'] = now.subtract(Duration(minutes: asInt(copy['minutesAgo']))).toUtc().toIso8601String();
    return OnlineOrder.fromJson(copy);
  }).toList();
}

const Map<String, String> kSyncTableByKey = {
  'products': 'products',
  'categories': 'categories',
  'settings': 'settings',
  'orders': 'orders',
  'pending': 'pending_orders',
  'online': 'online_orders',
};

const List<String> kSyncTables = [
  'products',
  'categories',
  'settings',
  'orders',
  'pending_orders',
  'online_orders',
];
