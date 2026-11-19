/* ============================================================
   MIE PANGSIT JAKARTA — POS local-first
   Data disimpan di localStorage (katalog, transaksi, sesi). QRIS
   dinamis dibuat di perangkat dari QRIS statis warung (tanpa
   server). Sinkronisasi antar-perangkat lewat backend IPOS
   (Node + Neon) — lihat js/sync.js dan Pengaturan → Server.
   ============================================================ */

(() => {
  'use strict';

  const STORAGE_KEYS = {
    products: 'mpj_pos_products',
    orders: 'mpj_pos_orders',
    settings: 'mpj_pos_settings',
    session: 'mpj_pos_session',
    theme: 'mpj_pos_theme',
    pending: 'mpj_pos_pending',
    online: 'mpj_pos_online',
    categories: 'mpj_pos_categories',
    snapshots: 'mpj_pos_snapshots',
    lastExport: 'mpj_pos_last_export',
    catalog: 'mpj_pos_catalog_version',
    cartTab: 'mpj_pos_cart_tab',
    sidebarHidden: 'mpj_pos_sidebar_hidden',
    cartData: 'mpj_pos_cart_data',
    users: 'mpj_pos_users'
  };

  // Naikkan tiap kali menu/kategori bawaan diganti, agar perangkat yang sudah
  // terpasang ikut mendapat katalog baru. Data lama disimpan sebagai snapshot dulu.
  const CATALOG_VERSION = 2;

  // Cadangan otomatis: SATU titik pemulihan lokal saja (yang lama diganti
  // otomatis) supaya penyimpanan perangkat tidak cepat penuh. Salinan lain
  // tetap ada di server (sinkronisasi) dan di file backup yang diunduh.
  const SNAPSHOT_LIMIT = 1;
  const SNAPSHOT_MAX_CHARS = 600 * 1024;
  // Batas total semua cadangan: jangan sampai storage penuh dan menggagalkan
  // penulisan transaksi/antrean (localStorage biasanya 5 MB per aplikasi)
  const SNAPSHOT_TOTAL_MAX_CHARS = 1.2 * 1024 * 1024;
  const STORAGE_SOFT_LIMIT_CHARS = 4 * 1024 * 1024; // di atas ini, cadangan lokal dipangkas otomatis
  const SNAPSHOT_EVERY_ORDERS = 10;
  let ordersSinceSnapshot = 0;
  let snapshotSeq = 0;
  let pendingRecoveryNote = ''; // pesan singkat kalau antrean sempat rusak lalu dipulihkan

  const CAT_MENU_PANGSIT = 'mie-pangsit-jakarta';
  const CAT_MIE_KERING = 'mie-kering';
  const CAT_SPECIAL = 'special-menu';

  const DEFAULT_PRODUCTS = [
    // Mie Pangsit Jakarta
    { id: 'pangsit-original', name: 'Mie Pangsit Original', category: CAT_MENU_PANGSIT, price: 20000, description: 'Pangsit dalam dibungkus mie dengan kuah bening gurih.', stock: null, available: true, emoji: '🍜' },
    { id: 'pangsit-pentol', name: 'Mie Pangsit Pentol', category: CAT_MENU_PANGSIT, price: 25000, description: 'Pangsit dalam isi pentol, level 1 sampai 3.', stock: null, available: true, emoji: '🥟' },
    { id: 'pangsit-ceker', name: 'Mie Pangsit Ceker', category: CAT_MENU_PANGSIT, price: 25000, description: 'Pangsit dalam isi ceker yang gurih.', stock: null, available: true, emoji: '🍗' },
    { id: 'pangsit-telur', name: 'Mie Pangsit Telur Puyuh', category: CAT_MENU_PANGSIT, price: 25000, description: 'Pangsit dalam isi telur puyuh.', stock: null, available: true, emoji: '🥚' },
    { id: 'paket-komplit', name: 'Mie Pangsit Komplit', category: CAT_MENU_PANGSIT, price: 30000, description: 'Isi lengkap: Pentol, Telur Puyuh, dan Ceker.', stock: null, available: true, emoji: '🎯' },
    // Mie Kering
    { id: 'mie-kering', name: 'Mie Kering (Level 1, 2, 3)', category: CAT_MIE_KERING, price: 20000, description: 'Mie kering dengan level kepedasan 1, 2, atau 3.', stock: null, available: true, emoji: '🥢' },
    { id: 'santuy', name: 'Mie Santuy', category: CAT_MIE_KERING, price: 15000, description: 'Mie rebus santuy khas warung.', stock: null, available: true, emoji: '🍜' },
    { id: 'guobiyos', name: 'Mie Guobiyos', category: CAT_MIE_KERING, price: 15000, description: 'Mie rebus dengan bumbu dan sambal khas.', stock: null, available: true, emoji: '🍲' },
    // Special menu
    { id: 'wonton-siomay-goreng', name: 'Wonton Siomay Goreng', category: CAT_SPECIAL, price: 15000, description: 'Wonton dan siomay digoreng sampai garing.', stock: null, available: true, emoji: '🥠' },
    { id: 'wonton-siomay', name: 'Wonton Siomay', category: CAT_SPECIAL, price: 15000, description: 'Wonton dan siomay rebus dengan saus.', stock: null, available: true, emoji: '🥟' },
    { id: 'bakso', name: 'Bakso', category: CAT_SPECIAL, price: 20000, description: 'Bakso dalam mangkuk dengan kuah kaldu.', stock: null, available: true, emoji: '🍲' },
    { id: 'mie-gurih', name: 'Mie Gurih', category: CAT_SPECIAL, price: 20000, description: 'Mie rebus gurih dengan topping.', stock: null, available: true, emoji: '🍜' },
    // Topping
    { id: 'telur-puyuh-topping', name: 'Telur Puyuh', category: 'topping', price: 6000, description: 'Telur puyuh rebus.', stock: null, available: true, emoji: '🥚' },
    { id: 'siomay-rebus', name: 'Siomay Rebus', category: 'topping', price: 6000, description: 'Siomay rebus dengan saus.', stock: null, available: true, emoji: '🥟' },
    { id: 'pentol', name: 'Pentol', category: 'topping', price: 6000, description: 'Pentol bakso rebus.', stock: null, available: true, emoji: '🍢' },
    { id: 'ceker', name: 'Ceker', category: 'topping', price: 6000, description: 'Ceker ayam rebus.', stock: null, available: true, emoji: '🍗' },
    // Minuman
    { id: 'teh-tawar', name: 'Teh Tawar', category: 'minuman', price: 4000, description: 'Teh tawar tanpa gula.', stock: null, available: true, emoji: '🍵' },
    { id: 'teh-es-panas', name: 'Teh Es/Panas', category: 'minuman', price: 6000, description: 'Teh es dengan gula atau teh panas.', stock: null, available: true, emoji: '🧋' },
    { id: 'air-mineral', name: 'Air Mineral', category: 'minuman', price: 6000, description: 'Air mineral dingin.', stock: null, available: true, emoji: '💧' },
    { id: 'kopi-hitam', name: 'Kopi Hitam', category: 'minuman', price: 8000, description: 'Kopi hitam tanpa gula.', stock: null, available: true, emoji: '☕' },
    { id: 'jeruk', name: 'Jeruk Es/Panas', category: 'minuman', price: 8000, description: 'Jus jeruk es atau hangat.', stock: null, available: true, emoji: '🍊' },
    { id: 'cappuccino', name: 'Cappuccino Es/Panas', category: 'minuman', price: 8000, description: 'Cappuccino es atau hangat.', stock: null, available: true, emoji: '☕' },
    { id: 'coklat', name: 'Cokelat Es/Panas', category: 'minuman', price: 10000, description: 'Cokelat es atau hangat.', stock: null, available: true, emoji: '🍫' },
    { id: 'lemon-tea', name: 'Lemon Tea Es/Panas', category: 'minuman', price: 12000, description: 'Teh lemon es atau hangat.', stock: null, available: true, emoji: '🍋' },
    { id: 'es-kelapa', name: 'Es Kelapa', category: 'minuman', price: 15000, description: 'Es kelapa muda segar.', stock: null, available: true, emoji: '🥥' }
  ];

  const DEFAULT_CATEGORIES = [
    { id: CAT_MENU_PANGSIT, label: 'Mie Pangsit Jakarta', emoji: '🍜' },
    { id: CAT_MIE_KERING, label: 'Mie Kering', emoji: '🥢' },
    { id: CAT_SPECIAL, label: 'Special menu', emoji: '🍢' },
    { id: 'topping', label: 'Topping', emoji: '🥟' },
    { id: 'minuman', label: 'Minuman', emoji: '🥤' }
  ];

  // Daftar emoji untuk dropdown kategori: daftar polos, tanpa keterangan —
// mengetik emoji di tablet sulit, jadi kasir cukup mengetuk lalu memilih.
  const CATEGORY_EMOJI_CHOICES = [
    '🍜', '🍲', '🍚', '🍝', '🍛', '🍱', '🥣', '🥢', '🍥',
    '🥟', '🥠', '🍢', '🍡', '🍗', '🍖', '🥘', '🍳',
    '🥗', '🥬', '🥒', '🍅', '🌽', '🍠', '🥔', '🍆',
    '🥤', '🧋', '☕', '🍵', '🧃', '🍶', '🥛', '🍹', '🥥', '🍋', '🍊', '💧',
    '🍰', '🍮', '🍪', '🍫', '🍭', '🍨', '🍦',
    '🍽️', '🍟', '⭐', '🔥', '✨', '🎯', '🌶️'
  ];
  const EMOJI_AUTO_ICON = '🔄'; // opsi "tebak otomatis dari nama kategori"

  function normalizeEmoji(value) {
    const text = String(value ?? '').trim();
    if (!text) return '';
    // variation selector (FE0F) sengaja dipertahankan agar emoji beranggota
    // tetap tampil sebagai emoji, bukan huruf; sisanya dibatasi 4 kode poin.
    return Array.from(text).filter((char) => char.codePointAt(0) > 31).slice(0, 4).join('');
  }

  function guessCategoryEmoji(label) {
    const text = String(label || '').toLowerCase();
    if (/minum|juice|es |teh|kop|susu|drink|air/.test(text)) return '🥤';
    if (/topping|pelengkap|tambahan|extra/.test(text)) return '🥟';
    if (/snack|camilan|keripik|cemilan/.test(text)) return '🍟';
    if (/nasi|rice/.test(text)) return '🍚';
    if (/sup|sc|p冷冻/.test(text)) return '🍲';
    if (/roti|bread|kue|cake|pastry/.test(text)) return '🍞';
    if (/sayur|vegetable|salad/.test(text)) return '🥗';
    if (/bubur|porridge/.test(text)) return '🥣';
    return '🍽️';
  }

  // Samakan bentuk data kategori (lama tanpa emoji tetap aman, dapat emoji default)
  function normalizeCategories(list) {
    if (!Array.isArray(list) || !list.length) return clone(DEFAULT_CATEGORIES);
    return list.filter((entry) => entry && entry.id).map((entry) => {
      const label = String(entry.label || entry.id).trim().slice(0, 24) || String(entry.id);
      return { id: String(entry.id), label, emoji: normalizeEmoji(entry.emoji) || guessCategoryEmoji(label) };
    });
  }

  const DEFAULT_SETTINGS = {
    businessName: 'Mie Pangsit Jakarta',
    businessAddress: 'Jl. Siradj Salman, Air Putih, Kec. Samarinda Ulu, Kota Samarinda, Kalimantan Timur 75124, Indonesia',
    businessPhone: '',
    taxRate: 11,
    qrisStaticPayload: '',
    receiptPaperSize: '58mm',
    receiptFooter: '',
    onlineRejectionMessage: 'Mohon maaf stok habis'
  };

  // Menu & Pengaturan hanya untuk akun pemilik; kasir cukup operasional.
  const OWNER_ONLY_VIEWS = ['menu', 'settings'];
  const OWNER_ONLY_ACTIONS = new Set(['open-product-modal', 'open-category-modal', 'export-data', 'import-data', 'snapshot-now', 'restore-snapshot', 'delete-snapshot', 'clear-history', 'load-users', 'user-edit', 'user-save', 'user-toggle', 'user-deactivate', 'delete-order']);

  let sessionLogoutTimer = null;

  // Akun mode lokal (tanpa server). Sandi disimpan di perangkat dan bisa
  // diganti lewat Pengaturan › Pengguna. Dipakai hanya selama alamat server
  // belum diatur — kalau server sudah diatur, akun divalidasi di server.
  const DEFAULT_LOCAL_USERS = [
    { username: 'pemilik', name: 'Pemilik', role: 'Pemilik', active: true, password: '1234' },
    { username: 'kasir', name: 'Kasir', role: 'Kasir', active: true, password: '1234' }
  ];

  function normalizeLocalUsers(list) {
    if (!Array.isArray(list) || !list.length) return clone(DEFAULT_LOCAL_USERS);
    const users = list
      .filter((item) => item && item.username)
      .map((item) => ({
        username: String(item.username).trim().toLowerCase(),
        name: String(item.name || item.username).trim().slice(0, 80) || String(item.username),
        role: item.role === 'Pemilik' ? 'Pemilik' : 'Kasir',
        active: item.active !== false,
        password: String(item.password || '')
      }))
      .filter((item) => item.username && item.password);
    return users.length ? users : clone(DEFAULT_LOCAL_USERS);
  }

  const localUsers = normalizeLocalUsers(load(null, STORAGE_KEYS.users));

  function findLocalUser(username) {
    const key = String(username || '').trim().toLowerCase();
    return localUsers.find((user) => user.username === key) || null;
  }

  function saveLocalUsers() {
    return save(STORAGE_KEYS.users, localUsers);
  }

  const ONLINE_PLATFORMS = {
    gofood: { label: 'GoFood' },
    shopee: { label: 'ShopeeFood' },
    grab: { label: 'GrabFood' },
    other: { label: 'Online' }
  };

  const ONLINE_STATUS = { baru: 'Baru', dibuat: 'Dibuat', siap: 'Siap diambil' };
  const ONLINE_STATUS_CLASS = { baru: 'pending', dibuat: 'local', siap: 'available' };

  function DUMMY_ONLINE_ORDERS() {
    const now = Date.now();
    return [
      { id: 'ONL-GF-2174', source: 'gofood', code: 'GF-2174', customer: 'Dina', note: 'Pedas level 2', status: 'baru', createdAt: new Date(now - 12 * 60000).toISOString(), items: [{ productId: 'pangsit-original', qty: 2 }, { productId: 'teh-es-panas', qty: 2 }] },
      { id: 'ONL-GR-9041', source: 'grab', code: 'GR-9041', customer: 'Rizky', note: '', status: 'dibuat', createdAt: new Date(now - 8 * 60000).toISOString(), items: [{ productId: 'bakso', qty: 1 }, { productId: 'paket-komplit', qty: 1 }, { productId: 'jeruk', qty: 1 }] },
      { id: 'ONL-SP-5512', source: 'shopee', code: 'SP-5512', customer: 'Maya', note: 'Saus sambal dipisah', status: 'siap', createdAt: new Date(now - 4 * 60000).toISOString(), items: [{ productId: 'mie-kering', qty: 2 }, { productId: 'lemon-tea', qty: 1 }] }
    ];
  }

  // Keranjang terakhir ikut disimpan: pesanan yang sedang dibayar (mis. hasil
  // "Lanjutkan ke pembayaran" lalu kasir menambah menu) tidak boleh lenyap saat
  // aplikasi dimuat ulang — dan tidak usah dikembalikan ke "Simpan, bayar nanti".
  const restoredCartData = loadCartData();

  const state = {
    products: load(DEFAULT_PRODUCTS, STORAGE_KEYS.products),
    orders: loadOrders(),
    settings: { ...DEFAULT_SETTINGS, ...(load(DEFAULT_SETTINGS, STORAGE_KEYS.settings) || {}) },
    categories: normalizeCategories(load(DEFAULT_CATEGORIES, STORAGE_KEYS.categories)),
    user: null,
    cart: restoredCartData.items,
    category: 'semua',
    search: '',
    menuFilter: 'all',
    orderType: restoredCartData.orderType,
    selectedPayment: 'cash',
    editingProductId: null,
    currentOrder: null,
    pendingOrders: loadPendingOrders(),
    onlineOrders: loadOnlineOrders(),
    cartTab: normalizeCartTab(load('cart', STORAGE_KEYS.cartTab)),
    sidebarHidden: !!load(false, STORAGE_KEYS.sidebarHidden),
    onlineStatusFilter: 'baru',
    onlinePlatformFilter: 'all',
    orderDetailTarget: null,
    onlineRejectOrderId: null,
    cartNoteOpenId: null
  };

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  document.addEventListener('DOMContentLoaded', init);

  function init() {
    if (!state.settings.receiptPaperSize) state.settings.receiptPaperSize = DEFAULT_SETTINGS.receiptPaperSize;
    delete state.settings.stockDeductionMode;
    // pulihkan isian keranjang terakhir SEBELUM render apa pun (renderCart ikut menulis ulang)
    if (restoredCartData.discount) $('#discountInput').value = restoredCartData.discount;
    if (restoredCartData.tableNumber) $('#tableNumber').value = restoredCartData.tableNumber;
    if (restoredCartData.note) $('#cartNoteInput').value = restoredCartData.note;
    applyOrderTypeUI();
    applyTheme(load('light', STORAGE_KEYS.theme) || 'light');
    const catalogUpdated = applyCatalogUpdate();
    bindEvents();
    renderCategoryTabs();
    renderCategoryOptions();
    if (catalogUpdated) renderAll();
    enforceSnapshotLimit(); // perangkat lama: rapikan 6 cadangan menjadi 1
    renderSnapshotList();
    if (catalogUpdated) showToast(`Katalog menu diperbarui: ${formatNumber(state.products.length)} menu. Riwayat transaksi tetap utuh.`);
    if (pendingRecoveryNote) showToast(pendingRecoveryNote, 8000);
    autoSnapshot('Aplikasi dibuka');
    updateClock();
    window.setInterval(updateClock, 30000);
    updateConnectionStatus();
    applySidebarHidden(); // samakan tampilan tombol/sidebar sebelum layar aplikasi muncul
    restoreSession();
    window.setInterval(checkSessionTimeout, 30000);
    window.addEventListener('focus', checkSessionTimeout);
    document.addEventListener('visibilitychange', checkSessionTimeout);
    startSync(); // sinkron antar-perangkat di latar belakang (tidak menghalangi kasir)
    /* APK Android: service worker tidak dipakai (file sudah lokal di
       perangkat) dan justru berisiko menyajikan aset lama setelah update —
       nonaktifkan + batal registrasi lama. Website biasa tetap memakai SW. */
    const isNativeApp = Boolean(window.Capacitor && typeof window.Capacitor.isNativePlatform === 'function' && window.Capacitor.isNativePlatform());
    if ('serviceWorker' in navigator) {
      if (isNativeApp) {
        navigator.serviceWorker.getRegistrations().then((list) => list.forEach((reg) => reg.unregister())).catch(() => undefined);
      } else {
        navigator.serviceWorker.register('sw.js').catch(() => undefined);
      }
    }
  }

  function clone(value) {
    if (typeof structuredClone === 'function') return structuredClone(value);
    return JSON.parse(JSON.stringify(value));
  }

  function load(fallback, key) {
    try {
      const raw = localStorage.getItem(key);
      if (!raw) return clone(fallback);
      const parsed = JSON.parse(raw);
      return parsed ?? clone(fallback);
    } catch (error) {
      console.warn('Gagal membaca data lokal', error);
      return clone(fallback);
    }
  }

  /* Menulis ke localStorage adalah satu-satunya cara data POS bertahan.
     Kegagalan menulis TIDAK boleh diam-diam: kalau tidak, pesanan yang
     baru dibuat hilang begitu aplikasi ditutup — kasir mengira "hilang
     sendiri". Tiap kegagalan memunculkan pita peringatan di layar. */
  function save(key, value) {
    let json;
    try {
      json = JSON.stringify(value);
    } catch (error) {
      console.warn('Data tidak bisa diubah menjadi teks', error);
      setStorageAlert(true, `Data "${key}" tidak bisa disimpan (isi tidak valid).`);
      return false;
    }
    if (writeKey(key, json)) {
      setStorageAlert(false);
      queueSync(key, value);
      return true;
    }
    // Penyimpanan penuh: pangkas titik pemulihan (cadangan) supaya transaksi
    // dan antrean tetap bisa tersimpan — data utama tidak boleh dikorbankan
    for (let attempt = 0; attempt < 4; attempt += 1) {
      if (!trimSnapshotsToBudget(json.length)) break;
      if (writeKey(key, json)) {
        setStorageAlert(false);
        queueSync(key, value);
        return true;
      }
    }
    setStorageAlert(true, 'Penyimpanan perangkat penuh — data terbaru BELUM tersimpan.');
    return false;
  }

  function writeKey(key, json) {
    try {
      localStorage.setItem(key, json);
      return true;
    } catch (error) {
      console.warn('Gagal menyimpan data lokal', error);
      return false;
    }
  }

  function setStorageAlert(isProblem, message) {
    const banner = elSafe('#storageAlert');
    if (banner) {
      banner.hidden = !isProblem;
      if (isProblem) banner.textContent = `⚠ ${message} Jangan tutup aplikasi — unduh backup di Pengaturan, lalu bersihkan data browser (cache situs) kalau tetap gagal.`;
    }
    if (!isProblem) return;
    showToast(message, 6000);
  }

  /* Pencarian elemen tanpa $: save() bisa dipanggil saat objek state sedang
     dibuat (sebelum variabel $ selesai diinisialisasi), jadi jangan sampai
     melempar ReferenceError dan membuat aplikasi gagal start. */
  function elSafe(selector) {
    try {
      return document && typeof document.querySelector === 'function' ? document.querySelector(selector) : null;
    } catch (error) {
      return null;
    }
  }

  function saveAll() {
    const results = [
      save(STORAGE_KEYS.products, state.products),
      save(STORAGE_KEYS.orders, state.orders),
      save(STORAGE_KEYS.settings, state.settings),
      save(STORAGE_KEYS.categories, state.categories),
      savePending(),
      saveOnline()
    ];
    return results.every(Boolean);
  }

  /* ---------- Katalog menu bawaan ----------
     Menu & kategori default diganti mengikuti daftar warung. Perangkat yang
     sudah terpasang otomatis dapat katalog baru; data menu lama diamankan
     sebagai snapshot lebih dulu. Riwayat transaksi tidak disentuh karena
     setiap baris order sudah menyimpan nama & harga saat transaksi dibuat. */
  function applyCatalogUpdate() {
    let storedVersion = 0;
    let hasStoredProducts = false;
    try {
      storedVersion = Number(localStorage.getItem(STORAGE_KEYS.catalog) || 0) || 0;
      hasStoredProducts = Boolean(localStorage.getItem(STORAGE_KEYS.products));
    } catch (error) {
      storedVersion = 0;
    }
    if (storedVersion >= CATALOG_VERSION) return false;
    if (hasStoredProducts) takeSnapshot('Sebelum katalog menu diperbarui');
    state.products = clone(DEFAULT_PRODUCTS);
    state.categories = normalizeCategories(DEFAULT_CATEGORIES);
    state.category = 'semua';
    state.search = '';
    state.menuFilter = 'all';
    const searchInput = $('#menuTableSearch');
    if (searchInput) searchInput.value = '';
    save(STORAGE_KEYS.products, state.products);
    save(STORAGE_KEYS.categories, state.categories);
    save(STORAGE_KEYS.catalog, CATALOG_VERSION);
    return true;
  }

  /* ---------- Cadangan otomatis (snapshot lokal) ----------
     Data POS hanya ada di perangkat ini. Setiap kali ada perubahan,
     simpan 6 titik pemulihan terakhir supaya data tidak hilang TOTAL
     walau cache browser dibersihkan atau file backup salah pilih. */
  function buildBackupPayload() {
    return {
      app: 'Mie Pangsit Jakarta POS',
      version: 4,
      exportedAt: new Date().toISOString(),
      products: state.products,
      orders: state.orders,
      settings: state.settings,
      categories: state.categories,
      pendingOrders: state.pendingOrders,
      onlineOrders: state.onlineOrders
    };
  }

  function takeSnapshot(reason) {
    const payload = buildBackupPayload();
    let json;
    try { json = JSON.stringify(payload); } catch (error) { return null; }
    // terlalu besar -> jangan ditimpan, agar penyimpanan tidak penuh dan data utama tetap aman
    if (json.length > SNAPSHOT_MAX_CHARS) return null;
    const list = load([], STORAGE_KEYS.snapshots);
    // id unik: dua snapshot bisa terjadi pada milidetik yang sama
    snapshotSeq += 1;
    list.unshift({ id: `snap-${Date.now()}-${snapshotSeq}`, at: new Date().toISOString(), reason, orders: state.orders.length, data: payload });
    // Hanya satu cadangan lokal yang disimpan; cadangan sebelumnya diganti.
    const kept = limitSnapshotList(list.slice(0, SNAPSHOT_LIMIT));
    if (!writeKey(STORAGE_KEYS.snapshots, JSON.stringify(kept))) return null;
    return kept[0] || null;
  }

  /* Buang titik pemulihan tertua sampai totalnya muat dalam batas.
     Dipakai juga saat penyimpanan penuh agar transaksi tetap bisa tersimpan. */
  function limitSnapshotList(list) {
    const kept = [];
    let used = 0;
    (Array.isArray(list) ? list : []).forEach((item) => {
      let size = 0;
      try { size = JSON.stringify(item).length; } catch (error) { size = SNAPSHOT_MAX_CHARS; }
      if (kept.length && used + size > SNAPSHOT_TOTAL_MAX_CHARS) return;
      kept.push(item);
      used += size;
    });
    return kept;
  }

  // Perangkat lama bisa masih menyimpan beberapa titik pemulihan. Saat aplikasi
  // dibuka, sisakan satu yang terbaru supaya penyimpanan tidak cepat penuh.
  function enforceSnapshotLimit() {
    const list = load([], STORAGE_KEYS.snapshots);
    if (!Array.isArray(list) || list.length <= SNAPSHOT_LIMIT) return false;
    return writeKey(STORAGE_KEYS.snapshots, JSON.stringify(list.slice(0, SNAPSHOT_LIMIT)));
  }

  function trimSnapshotsToBudget(reserveChars = 0) {
    const list = load([], STORAGE_KEYS.snapshots);
    if (!Array.isArray(list) || !list.length) return false;
    const budget = STORAGE_SOFT_LIMIT_CHARS - reserveChars;
    const base = storageUsage(STORAGE_KEYS.snapshots); // pemakaian selain kunci cadangan
    const kept = [];
    let used = 0;
    // urutan: terbaru dulu; yang tidak muat -&gt; titik pemulihan tertua dibuang
    list.forEach((item) => {
      let size = 0;
      try { size = STORAGE_KEYS.snapshots.length + JSON.stringify(item).length; } catch (error) { size = SNAPSHOT_MAX_CHARS; }
      if (kept.length && base + used + size > budget) return;
      kept.push(item);
      used += size;
    });
    if (kept.length === list.length) return false;
    if (!writeKey(STORAGE_KEYS.snapshots, JSON.stringify(kept))) return false;
    console.info(`Cadangan lokal dipangkas menjadi ${kept.length} titik agar penyimpanan tidak penuh`);
    return true;
  }

  function storageUsage(excludeKey) {
    let total = 0;
    try {
      if (typeof localStorage.length !== 'number') return 0;
      for (let index = 0; index < localStorage.length; index += 1) {
        const key = localStorage.key(index) || '';
        if (excludeKey && key === excludeKey) continue;
        total += key.length + (localStorage.getItem(key) || '').length;
      }
    } catch (error) {
      return 0;
    }
    return total;
  }

  function autoSnapshot(reason) {
    const list = load([], STORAGE_KEYS.snapshots);
    const newest = list[0];
    if (newest && newest.orders === state.orders.length) return false; // belum ada transaksi baru
    takeSnapshot(reason);
    return true;
  }

  function noteOrderSaved() {
    ordersSinceSnapshot += 1;
    if (ordersSinceSnapshot >= SNAPSHOT_EVERY_ORDERS) {
      ordersSinceSnapshot = 0;
      autoSnapshot(`Otomatis — tiap ${SNAPSHOT_EVERY_ORDERS} transaksi`);
    }
  }

  function renderSnapshotList() {
    const list = load([], STORAGE_KEYS.snapshots);
    const listEl = $('#snapshotList');
    const statusEl = $('#backupStatus');
    if (!listEl || !statusEl) return;
    const lastExport = load(null, STORAGE_KEYS.lastExport);
    const parts = [`${list.length} titik pemulihan tersimpan di perangkat`];
    if (list[0]) parts.push(`terakhir ${formatDateTime(list[0].at)} (${list[0].reason})`);
    if (lastExport) parts.push(`file backup terakhir ${formatDateTime(lastExport)}`);
    statusEl.textContent = `${parts.join(' · ')}.`;
    const warnEl = $('#backupWarning');
    if (warnEl) warnEl.hidden = Boolean(lastExport);
    if (!list.length) {
      listEl.innerHTML = '<p class="settings-hint">Belum ada cadangan otomatis.</p>';
      return;
    }
    listEl.innerHTML = list.map((item) => `
      <div class="snapshot-row">
        <span><strong>${formatDateTime(item.at)}</strong><small>${escapeHtml(item.reason)} · ${item.orders} transaksi · ${snapshotSizeLabel(item)}</small></span>
        <span class="snapshot-actions">
          <button class="text-button" type="button" data-action="restore-snapshot" data-snapshot-id="${escapeAttr(item.id)}">Kembalikan</button>
          <button class="text-button snapshot-delete" type="button" data-action="delete-snapshot" data-snapshot-id="${escapeAttr(item.id)}" title="Hapus cadangan ini saja" aria-label="Hapus cadangan ${escapeAttr(formatDateTime(item.at))}">Hapus</button>
        </span>
      </div>`).join('');
  }

  // Perkiraan ruang yang dipakai satu cadangan (localStorage = UTF-16, ±2 byte/karakter).
  function snapshotSizeLabel(item) {
    let chars = 0;
    try { chars = JSON.stringify(item).length; } catch (error) { chars = 0; }
    return `${formatNumber(Math.max(1, Math.round((chars * 2) / 1024)))} KB`;
  }

  function applyBackupPayload(data) {
    state.products = Array.isArray(data.products) ? data.products : state.products;
    state.orders = Array.isArray(data.orders) ? data.orders : state.orders;
    state.settings = { ...DEFAULT_SETTINGS, ...(data.settings || {}) };
    state.categories = normalizeCategories(data.categories);
    // File backup versi lama tidak punya daftar antrean. Kalau field-nya tidak ada,
    // JANGAN dikosongkan — pesanan yang sedang dibuat harus tetap utuh.
    state.pendingOrders = Array.isArray(data.pendingOrders) ? normalizePendingList(data.pendingOrders) : state.pendingOrders.slice();
    state.onlineOrders = Array.isArray(data.onlineOrders) ? data.onlineOrders : load(DUMMY_ONLINE_ORDERS(), STORAGE_KEYS.online);
    saveAll();
    renderAll();
    renderSnapshotList();
  }

  /* ---------- Antrean "Pesanan dibuat" ----------
     Daftar ini yang paling sering dikeluhkan "hilang sendiri". Tiga pagar
     dari kemungkinan itu:
     1) penyimpanan rusak -> dipulihkan dari cadangan lokal, bukan jadi kosong;
     2) isi entri rusak (tanpa item, id dobel) -> dibetulkan, bukan dibiarkan;
     3) tidak ada satu pun menu yang cocok -> pesanan tetap ada, kasir diberi tahu. */
  /* ---------- Transaksi (riwayat) ----------
     Satu baris rusak di riwayat tidak boleh membuat dasbor, laporan, atau struk
     kosong. Semua tampilan memakai orderItems() supaya data aneh dilewati, bukan
     melempar error. */
  function orderItems(order) {
    if (!order || typeof order !== 'object' || !Array.isArray(order.items)) return [];
    return order.items
      .filter((item) => item && typeof item === 'object')
      .map((item) => {
        const qty = Math.max(1, Math.floor(Number(item.qty) || 0) || 1);
        const price = Math.max(0, Number(item.price) || 0);
        return { ...item, name: String(item.name || 'Menu'), price, qty, total: Math.max(0, Number(item.total) || price * qty) };
      });
  }

  function normalizeOrders(list) {
    if (!Array.isArray(list)) return [];
    const used = new Set();
    let repairedDates = 0;
    const result = list.filter((order) => order && typeof order === 'object').map((order) => {
      const fixed = { ...order, items: orderItems(order) };
      if (!fixed.id) fixed.id = `MPJ-DIPULIH-${used.size + 1}`;
      if (used.has(fixed.id)) {
        let suffix = 2;
        while (used.has(`${fixed.id}-${suffix}`)) suffix += 1;
        fixed.id = `${fixed.id}-${suffix}`;
      }
      used.add(fixed.id);
      if (!Number.isFinite(Number(fixed.total))) fixed.total = 0;
      if (!Number.isFinite(Number(fixed.subtotal))) fixed.subtotal = fixed.total;
      // tanggal rusak -> transaksi tetap dihitung pada hari ini, jangan hilang dari laporan
      if (!safeDate(fixed.createdAt)) { fixed.createdAt = new Date().toISOString(); repairedDates += 1; }
      return fixed;
    });
    if (repairedDates) console.warn(`${repairedDates} transaksi ber tanggal rusak diperbaiki ke hari ini`);
    return result;
  }

  function loadOnlineOrders() {
    const list = load(DUMMY_ONLINE_ORDERS(), STORAGE_KEYS.online);
    if (!Array.isArray(list)) return DUMMY_ONLINE_ORDERS();
    return list.filter((order) => order && typeof order === 'object');
  }

  function loadOrders() {
    const list = load([], STORAGE_KEYS.orders);
    const normalized = normalizeOrders(list);
    // perbaiki yang bisa diperbaiki, lalu simpan ulang supaya tidak terulang tiap muat
    if (JSON.stringify(normalized) !== JSON.stringify(list)) save(STORAGE_KEYS.orders, normalized);
    return normalized;
  }

  function normalizePendingOrder(entry, index = 0) {
    if (!entry || typeof entry !== 'object') return null;
    const items = (Array.isArray(entry.items) ? entry.items : []).map((item) => {
      if (!item || typeof item !== 'object') return null;
      const qty = Math.max(1, Math.floor(Number(item.qty) || 0) || 1);
      const price = Math.max(0, Number(item.price) || 0);
      return {
        productId: item.productId || '',
        name: String(item.name || 'Menu'),
        price,
        qty,
        total: Math.max(0, Number(item.total) || price * qty),
        note: String(item.note || '').slice(0, 120)
      };
    }).filter(Boolean);
    if (!items.length) return null;
    const itemsTotal = items.reduce((sum, item) => sum + item.total, 0);
    const discount = Math.min(Math.max(Number(entry.discount) || 0, 0), itemsTotal);
    return {
      ...entry,
      id: entry.id || `HOLD-DIPULIH-${index + 1}`,
      createdAt: entry.createdAt || new Date().toISOString(),
      orderType: entry.orderType || 'dine-in',
      tableNumber: entry.tableNumber || '',
      items,
      subtotal: Number.isFinite(Number(entry.subtotal)) ? Number(entry.subtotal) : itemsTotal,
      discount,
      total: Number.isFinite(Number(entry.total)) ? Number(entry.total) : Math.max(0, itemsTotal - discount),
      status: entry.status === 'preparing' ? 'preparing' : 'pending',
      payment: entry.payment || null
    };
  }

  function normalizePendingList(list) {
    if (!Array.isArray(list)) return [];
    const used = new Set();
    return list
      .map((entry, index) => normalizePendingOrder(entry, index))
      .filter(Boolean)
      .map((order) => {
        if (!used.has(order.id)) {
          used.add(order.id);
          return order;
        }
        // id kembar: jangan dibuang pesanannya, beri id unik agar tidak terhapus bareng
        let suffix = 2;
        while (used.has(`${order.id}-${suffix}`)) suffix += 1;
        const fixed = { ...order, id: `${order.id}-${suffix}` };
        used.add(fixed.id);
        return fixed;
      });
  }

  function loadPendingOrders() {
    let raw = null;
    try { raw = localStorage.getItem(STORAGE_KEYS.pending); } catch (error) { raw = null; }
    if (!raw) return [];
    let parsed = null;
    let readable = true;
    try {
      parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) readable = false;
    } catch (error) {
      readable = false;
    }
    if (!readable) {
      const recovered = recoverPendingFromSnapshots();
      pendingRecoveryNote = recovered.length
        ? `${recovered.length} pesanan dibuat dipulihkan dari cadangan lokal (data tersimpan sempat rusak).`
        : 'Data pesanan dibuat tidak terbaca dan tidak ada cadangan yang memuatnya.';
      if (recovered.length) save(STORAGE_KEYS.pending, recovered);
      return recovered;
    }
    const list = normalizePendingList(parsed);
    if (list.length !== parsed.length) save(STORAGE_KEYS.pending, list); // rapikan yang bisa dirapikan
    return list;
  }

  function recoverPendingFromSnapshots() {
    const list = load([], STORAGE_KEYS.snapshots);
    const snapshots = Array.isArray(list) ? list : [];
    for (const snapshot of snapshots) {
      const data = snapshot && snapshot.data;
      if (data && Array.isArray(data.pendingOrders) && data.pendingOrders.length) {
        return normalizePendingList(data.pendingOrders);
      }
    }
    return [];
  }

  function savePending() {
    state.pendingOrders = normalizePendingList(state.pendingOrders);
    return save(STORAGE_KEYS.pending, state.pendingOrders);
  }

  // Hapus hanya entri pertama dengan id tersebut: id kembar tidak boleh ikut hilang
  function removePendingOrder(orderId) {
    const index = state.pendingOrders.findIndex((pending) => pending.id === orderId);
    if (index === -1) return false;
    state.pendingOrders.splice(index, 1);
    savePending();
    return true;
  }

  function saveOnline() {
    return save(STORAGE_KEYS.online, state.onlineOrders);
  }

  /* Kalau POS dibuka di dua tab sekaligus, tab yang menulis terakhir akan
     menimpa daftar "Pesanan dibuat" milik tab lain — dari sisi kasir itu
     pesanan hilang sendiri. Jadi setiap perubahan penyimpanan dari tab lain
     langsung dibaca ulang, bukan dibiarkan tertimpa diam-diam. */
  const SYNC_STORAGE_KEYS = [STORAGE_KEYS.pending, STORAGE_KEYS.online, STORAGE_KEYS.orders, STORAGE_KEYS.products, STORAGE_KEYS.categories, STORAGE_KEYS.snapshots];
  function handleStorageSync(event) {
    const key = event && event.key;
    if (key === STORAGE_KEYS.session) {
      if (!event.newValue && state.user) {
        logout();
        showToast('Sesi sudah berakhir. Silakan masuk kembali.');
      } else if (event.newValue) {
        restoreSession();
      }
      return;
    }
    const changed = key ? [key] : SYNC_STORAGE_KEYS.slice();
    if (!changed.some((item) => SYNC_STORAGE_KEYS.includes(item))) return;
    const modalOpen = hasOpenModal();
    changed.forEach((item) => {
      if (item === STORAGE_KEYS.pending) state.pendingOrders = loadPendingOrders();
      else if (item === STORAGE_KEYS.online) state.onlineOrders = loadOnlineOrders();
      else if (item === STORAGE_KEYS.orders) state.orders = loadOrders();
      else if (item === STORAGE_KEYS.products && !modalOpen) state.products = load(DEFAULT_PRODUCTS, STORAGE_KEYS.products);
      else if (item === STORAGE_KEYS.categories && !modalOpen) state.categories = normalizeCategories(load(DEFAULT_CATEGORIES, STORAGE_KEYS.categories));
      else if (item === STORAGE_KEYS.snapshots) renderSnapshotList();
    });
    renderQueues();
    if (changed.includes(STORAGE_KEYS.orders)) { renderDashboard(); renderReports(); }
    if (!modalOpen && (changed.includes(STORAGE_KEYS.products) || changed.includes(STORAGE_KEYS.categories))) {
      renderCategoryTabs();
      renderCategoryOptions();
      renderProducts();
      renderMenuTable();
      renderCart();
    }
    showToast('Data disinkronkan dari tab lain yang terbuka.');
  }

  function hasOpenModal() {
    return $$('.modal').some((modal) => !modal.hidden);
  }

  function bindEvents() {
    $('#loginForm').addEventListener('submit', handleLogin);
    $('#productForm').addEventListener('submit', handleProductSubmit);
    $('#categoryAddForm').addEventListener('submit', handleCategoryAdd);
    $('#businessForm').addEventListener('submit', handleBusinessSubmit);
    $('#qrisForm').addEventListener('submit', handleQrisSubmit);
    const qrisImageInput = $('#qrisImageInput');
    if (qrisImageInput) qrisImageInput.addEventListener('change', handleQrisImageUpload);
    $('#receiptFooterForm').addEventListener('submit', handleReceiptFooterSubmit);
    $('#onlineRejectReasonForm').addEventListener('submit', submitOnlineRejection);
    const apiConfigForm = $('#apiConfigForm');
    if (apiConfigForm) apiConfigForm.addEventListener('submit', handleApiConfigSubmit);
    const userForm = $('#userForm');
    if (userForm) userForm.addEventListener('submit', handleUserFormSubmit);
    $('#printerModel').addEventListener('change', handlePrinterModelChange);
    $('#printerDevice').addEventListener('change', handlePrinterDeviceChange);
    $('#menuSearch').addEventListener('input', (event) => { state.search = event.target.value.trim().toLowerCase(); renderProducts(); });
    $('#menuTableSearch').addEventListener('input', renderMenuTable);
    $('#reportFrom').addEventListener('change', updateReportDateLimits);
    $('#reportTo').addEventListener('change', updateReportDateLimits);
    $('#discountInput').addEventListener('input', renderCart);
    $('#cashReceived').addEventListener('input', renderChange);
    $('#receiptPaperSize').addEventListener('change', (event) => {
      state.settings.receiptPaperSize = event.target.value;
      save(STORAGE_KEYS.settings, state.settings);
      applyReceiptPaperSize();
      showToast(`Kertas cetak disetel ke ${event.target.selectedOptions[0].textContent}.`);
    });
    $('#checkoutButton').addEventListener('click', () => openCheckout());
    $('#completePayment').addEventListener('click', completePayment);
    $('#importFile').addEventListener('change', importDataFile);
    document.addEventListener('click', handleDocumentClick);
    document.addEventListener('input', handleDocumentInput);
    const modalBackdropEl = $('#modalBackdrop');
    if (modalBackdropEl) modalBackdropEl.addEventListener('click', () => {
      if (!$('#paymentConfirmModal').hidden) cancelPaymentConfirmation();
      else closeModal();
    });
    window.addEventListener('online', updateConnectionStatus);
    window.addEventListener('offline', updateConnectionStatus);
    window.addEventListener('storage', handleStorageSync);
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        if (!$('#paymentConfirmModal').hidden) cancelPaymentConfirmation();
        else closeModal();
        closeSidebar();
      }
    });
  }

  function apiBaseUrl() {
    try { return (window.MPJConfig && window.MPJConfig.getApiBase()) || ''; } catch (error) { return ''; }
  }

  function apiToken() {
    try { return localStorage.getItem('mpj_api_token') || ''; } catch (error) { return ''; }
  }

  function setApiToken(value) {
    try {
      if (value) localStorage.setItem('mpj_api_token', value);
      else localStorage.removeItem('mpj_api_token');
    } catch (error) { /* penyimpanan tidak tersedia */ }
  }

  async function handleLogin(event) {
    event.preventDefault();
    const username = $('#loginName').value.trim().toLowerCase();
    const password = $('#loginPassword').value;
    const errorEl = $('#loginError');
    errorEl.hidden = true;

    // Kalau alamat server sudah diatur, login divalidasi di server (sandi
    // disimpan sebagai hash di database — tidak lagi ada di aplikasi).
    const base = apiBaseUrl();
    if (base) {
      try {
        const response = await fetch(base + '/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username, password })
        });
        let body = null;
        try { body = await response.json(); } catch (error) { body = null; }
        if (!response.ok) {
          errorEl.textContent = (body && body.error) || 'Nama pengguna atau sandi salah.';
          errorEl.hidden = false;
          return;
        }
        setApiToken(body && body.token ? body.token : '');
        const serverUser = (body && body.user) || {};
        loginAsUser({
          username: serverUser.username || username,
          name: serverUser.name || serverUser.username || username,
          role: serverUser.role || 'Kasir'
        });
        return;
      } catch (error) {
        errorEl.textContent = 'Tidak bisa menghubungi server. Periksa internet atau alamat server di Pengaturan.';
        errorEl.hidden = false;
        return;
      }
    }

    // Mode lokal (server belum diatur): pakai akun di perangkat ini, yang bisa
    // ditambah/diubah lewat Pengaturan › Pengguna. Sandi bawaan: 1234.
    const localUser = findLocalUser(username);
    if (!localUser || localUser.active === false || password !== localUser.password) {
      errorEl.textContent = 'Nama pengguna atau sandi salah. Akun bawaan: pemilik / 1234.';
      errorEl.hidden = false;
      return;
    }
    loginAsUser({ username: localUser.username, name: localUser.name, role: localUser.role });
  }

  function loginAsUser(user) {
    const loginAt = Date.now();
    state.user = {
      username: user.username,
      name: user.name,
      role: user.role,
      loginAt,
      loginDay: localDayKey(loginAt),
      loginMinute: localMinuteOfDay(loginAt)
    };
    save(STORAGE_KEYS.session, state.user);
    scheduleSessionLogout();
    $('#loginError').hidden = true;
    showApp();
    showToast(`Selamat datang, ${user.name}.`);
    // Sesi baru: segera tarik/kirim data lewat server (kalau sudah diatur).
    if (typeof MPJSync !== 'undefined' && MPJSync.isConfigured && MPJSync.isConfigured()) {
      try { MPJSync.syncNow(); } catch (error) { /* diabaikan */ }
    }
  }


  function showLogin() {
    $('#loginScreen').classList.remove('is-hidden');
    $('#posShell').classList.add('is-hidden');
    $('#loginName').focus();
  }

  function showApp() {
    $('#loginScreen').classList.add('is-hidden');
    $('#posShell').classList.remove('is-hidden');
    $('#userName').textContent = state.user.name;
    $('#userRole').textContent = state.user.role;
    $('#greetingName').textContent = state.user.name;
    $('#userAvatar').textContent = state.user.name.charAt(0).toUpperCase();
    updateBusinessLabels();
    hydrateSettingsForm();
    const today = dateKey();
    // Buka Laporan langsung ke "Hari ini" supaya tidak tertukar dengan hitungan
    // mingguan. Rentang mingguan tetap bisa dipilih lewat tombol cepat / Export Mingguan.
    $('#reportFrom').value = today;
    $('#reportTo').value = today;
    updateReportDateLimits();
    renderDashboard();
    renderProducts();
    renderCart();
    renderQueues();
    renderMenuTable();
    renderReports();
    switchCartTab(state.cartTab); // kembali ke tab yang terakhir dipakai (mis. "Dibuat")
    applySidebarHidden(); // terapkan pilihan tampilan sidebar (tersembunyi/tampil)
    applyRoleAccess(); // kasir: sembunyikan Menu & Pengaturan (milik pemilik)
    if (state.cart.length) {
      // hasil "Lanjutkan ke pembayaran" + menu tambahan masih ada — jangan dikira hilang
      showToast(`Keranjang sebelumnya masih ada: ${formatNumber(state.cart.reduce((sum, item) => sum + item.qty, 0))} item. Lanjutkan bayar atau tekan "Kosongkan".`, 5000);
    }
    navigate('dashboard');
  }

  /* ---------- Akses peran ----------
     Kasir hanya operasional: Menu dan Pengaturan adalah milik pemilik. */
  function isOwnerUser() {
    return Boolean(state.user && state.user.role === 'Pemilik');
  }

  function applyRoleAccess() {
    const owner = isOwnerUser();
    $$('[data-view="menu"], [data-view="settings"]').forEach((el) => { el.hidden = !owner; });
    $$('[data-go-view="menu"]').forEach((el) => { el.hidden = !owner; });
  }

  function handleDocumentClick(event) {
    // Simpan lokasi klik sebelum handler aksi merender ulang isi keranjang.
    // Render bisa melepas target lama dari DOM sehingga pemeriksaan di akhir
    // event mengira klik berasal dari luar panel dan menutupnya.
    const keepOrdersSliderOpen = Boolean(
      event.target.closest('#ordersSlider')
      || event.target.closest('#ordersSliderHandle')
      || event.target.closest('.topbar-cart-tabs')
      || event.target.closest('[data-add-product]')
      || event.target.closest('.product-panel')
    );
    const actionEl = event.target.closest('[data-action]');
    const viewEl = event.target.closest('[data-view], [data-go-view]');
    const categoryEl = event.target.closest('[data-category]');
    const orderTypeEl = event.target.closest('[data-order-type]');
    const paymentEl = event.target.closest('[data-payment]');
    const addEl = event.target.closest('[data-add-product]');
    const quantityEl = event.target.closest('[data-quantity-action]');
    const editProductEl = event.target.closest('[data-edit-product]');
    const deleteProductEl = event.target.closest('[data-delete-product]');
    const toggleProductEl = event.target.closest('[data-toggle-product]');
    const deleteCategoryEl = event.target.closest('[data-delete-category]');
    const menuFilterEl = event.target.closest('[data-menu-filter]');
    const reportRangeEl = event.target.closest('[data-report-range]');
    const cartTabEl = event.target.closest('[data-cart-tab]');
    const pendingRowEl = event.target.closest('[data-pending-id]');
    const onlineRowEl = event.target.closest('[data-online-id]');
    const cartNoteEl = event.target.closest('[data-cart-item-note]');
    const settingsTabEl = event.target.closest('[data-settings-tab]');

    if (viewEl) navigate(viewEl.dataset.goView || viewEl.dataset.view);
    if (categoryEl) {
      state.category = categoryEl.dataset.category;
      $$('#categoryTabs button').forEach((button) => {
        const active = button === categoryEl;
        button.classList.toggle('is-active', active);
        button.setAttribute('aria-pressed', String(active));
      });
      renderProducts();
    }
    if (orderTypeEl) {
      state.orderType = orderTypeEl.dataset.orderType;
      $$('#orderTypeTabs button').forEach((button) => {
        const active = button === orderTypeEl;
        button.classList.toggle('is-active', active);
        button.setAttribute('aria-pressed', String(active));
      });
      $('#tableField').classList.toggle('is-visible', state.orderType === 'dine-in');
      renderProducts();
      renderCart();
    }
    if (paymentEl) selectPayment(paymentEl.dataset.payment);
    if (addEl) {
      const added = addToCart(addEl.dataset.addProduct);
      // Kasir sedang membuka daftar "Bayar nanti" atau "Online": begitu kartu
      // menu ditekan, panel otomatis pindah ke tab Keranjang supaya menu yang
      // baru masuk langsung terlihat (tidak perlu tekan tab Keranjang lagi).
      const sliderEl = $('#ordersSlider');
      if (added && sliderEl && sliderEl.classList.contains('is-open')
        && (state.cartTab === 'pending' || state.cartTab === 'online')) {
        switchCartTab('cart');
      }
    }
    if (quantityEl) changeCartQuantity(quantityEl.dataset.productId, Number(quantityEl.dataset.quantityAction));
    // Klik baris menu di keranjang membuka/mentup kotak "catatan per menu".
    // Klik pada tombol ± atau di dalam kotak catatan tidak ikut membuka/tutup.
    if (cartNoteEl && !event.target.closest('button') && !event.target.closest('input, textarea')) {
      toggleCartNote(cartNoteEl.dataset.cartItemNote);
    }
    if (editProductEl) openProductModal(editProductEl.dataset.editProduct);
    if (deleteProductEl) deleteProduct(deleteProductEl.dataset.deleteProduct);
    if (toggleProductEl) toggleProductAvailability(toggleProductEl.dataset.toggleProduct);
    if (deleteCategoryEl) deleteCategory(deleteCategoryEl.dataset.deleteCategory);
    if (menuFilterEl) {
      state.menuFilter = menuFilterEl.dataset.menuFilter;
      $$('#menuFilter button').forEach((button) => {
        const active = button === menuFilterEl;
        button.classList.toggle('is-active', active);
        button.setAttribute('aria-pressed', String(active));
      });
      renderMenuTable();
    }
    if (settingsTabEl) applySettingsTab(settingsTabEl.dataset.settingsTab);
    if (reportRangeEl) applyQuickRange(reportRangeEl.dataset.reportRange);
    if (cartTabEl) {
      switchCartTab(cartTabEl.dataset.cartTab);
      // Menu sekarang satu layar penuh — tab topbar membuka panel geser
      toggleOrdersSlider(true);
    }
    // Tombol di dalam kartu (mis. ✕ batal) memproses aksinya sendiri —
    // klik di atasnya jangan ikut membuka detail pesanan.
    const innerQueueAction = actionEl && (actionEl.closest('[data-pending-id]') || actionEl.closest('[data-online-id]'));
    if (pendingRowEl && !innerQueueAction) openOrderDetail('pending', pendingRowEl.dataset.pendingId);
    if (onlineRowEl && !innerQueueAction) openOrderDetail('online', onlineRowEl.dataset.onlineId);
    if (actionEl) handleAction(actionEl.dataset.action, actionEl);
    // Panel "Pesanan" juga menutup saat kasir menyentuh/mengklik di luar panel
    // (menu kasir, topbar, dll) — tidak harus mencari tombol ×.
    const sliderEl = $('#ordersSlider');
    if (sliderEl && sliderEl.classList.contains('is-open')
      && !keepOrdersSliderOpen) {
      toggleOrdersSlider(false);
    }
  }

  function handleAction(action, actionEl) {
    if (state.user && !isOwnerUser() && OWNER_ONLY_ACTIONS.has(action)) {
      showToast('Fitur ini hanya bisa dipakai oleh akun pemilik.');
      return;
    }
    switch (action) {
      case 'logout': logout(); break;
      case 'toggle-password': togglePassword(); break;
      case 'toggle-theme': toggleTheme(); break;
      case 'open-sidebar': openSidebar(); break;
      case 'close-sidebar': closeSidebar(); break;
      case 'toggle-sidebar': toggleSidebar(); break;
      case 'clear-cart': clearCart(); break;
      case 'open-product-modal': openProductModal(); break;
      case 'open-category-modal': openCategoryModal(); break;
      case 'close-modal': closeModal(); break;
      case 'cancel-payment-confirm': cancelPaymentConfirmation(); break;
      case 'confirm-payment': confirmPaymentReceived(); break;
      case 'new-order': newOrder(); break;
      case 'hold-order': holdOrder(); break;
      case 'add-more-items': addMoreItems(); break;
      case 'online-status-filter': setOnlineStatusFilter(actionEl ? actionEl.dataset.status : ''); break;
    case 'online-platform-filter': setOnlinePlatformFilter(actionEl ? actionEl.dataset.platform : 'all'); break;
      case 'resume-pending': resumePendingOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'finish-pending': finishPendingOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'cancel-pending': cancelPendingOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'toggle-orders-slider': toggleOrdersSlider(); break;
      case 'advance-online': advanceOnlineOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'cancel-online': cancelOnlineOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'print-online-ticket': printOnlineTicketById(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'print-receipt': printReceipt(); break;
      case 'reprint-order': reprintOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'delete-order': deleteReportOrder(actionEl ? actionEl.dataset.orderId : ''); break;
      case 'export-report': exportReport(); break;
      case 'export-report-today': exportReportPreset('today'); break;
      case 'export-report-week': exportReportPreset('week'); break;
      case 'refresh-report': renderReports(); break;
      case 'refresh-bt-devices': refreshBluetoothDevices(); break;
      case 'test-bt-print': testBluetoothPrint(); break;
      case 'open-bt-settings': openBluetoothSettings(); break;
      case 'export-data': exportData(); break;
      case 'snapshot-now': takeSnapshotNow(); break;
      case 'upload-qris-image': { const qrisInput = $('#qrisImageInput'); if (qrisInput) qrisInput.click(); break; }
      case 'restore-snapshot': restoreSnapshot(actionEl ? actionEl.dataset.snapshotId : ''); break;
      case 'delete-snapshot': deleteSnapshot(actionEl ? actionEl.dataset.snapshotId : ''); break;
      case 'import-data': $('#importFile').click(); break;
      case 'sync-now': runManualSync(); break;
      case 'clear-history': clearTransactionHistory(); break;
      case 'load-users': loadUsers(); break;
      case 'user-edit': startUserEdit(actionEl ? actionEl.dataset.userKey : ''); break;
      case 'user-edit-cancel': cancelUserEdit(); break;
      case 'user-save': saveUser(actionEl); break;
      case 'user-toggle': toggleUserActive(actionEl ? actionEl.dataset.userKey : ''); break;
      case 'user-deactivate': toggleUserActive(actionEl ? actionEl.dataset.userKey : ''); break;
      default: break;
    }
  }

  /* ---------- Sub-pengaturan ----------
     Halaman Pengaturan dipecah jadi beberapa kelompok (tab di atas). Hanya
     kelompok yang dipilih yang ditampilkan supaya tidak perlu menggulir jauh. */
  function applySettingsTab(name) {
    const tabs = $$('#settingsTabs [data-settings-tab]');
    if (!tabs.length) return;
    const valid = name && tabs.some((tab) => tab.dataset.settingsTab === name) ? name : tabs[0].dataset.settingsTab;
    tabs.forEach((tab) => {
      const active = tab.dataset.settingsTab === valid;
      tab.classList.toggle('is-active', active);
      tab.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    $$('[data-settings-panel]').forEach((panel) => {
      panel.classList.toggle('is-active', panel.dataset.settingsPanel === valid);
    });
    if (valid === 'pengguna') openUsersPanel();
  }

  function navigate(view) {
    let target = $(`[data-view-panel="${view}"]`) ? view : 'dashboard';
    if (state.user && !isOwnerUser() && OWNER_ONLY_VIEWS.includes(target)) {
      showToast('Menu dan Pengaturan hanya bisa dibuka oleh akun pemilik.');
      target = 'dashboard';
    }
    $$('.pos-nav-item').forEach((item) => {
      const active = item.dataset.view === target;
      item.classList.toggle('is-active', active);
      if (active) item.setAttribute('aria-current', 'page');
      else item.removeAttribute('aria-current');
    });
    $$('[data-view-panel]').forEach((panel) => panel.classList.toggle('is-active', panel.dataset.viewPanel === target));
    const headings = {
      dashboard: ['Ringkasan hari ini', 'Dashboard Kasir'],
      cashier: ['Kasir', 'Transaksi baru'],
      menu: ['Katalog warung', 'Menu'],
      reports: ['Analisis penjualan', 'Laporan'],
      settings: ['Konfigurasi sistem', 'Pengaturan']
    };
    $('#topbarKicker').textContent = headings[target][0];
    $('#topbarTitle').textContent = headings[target][1];
    // Tab Keranjang/Dibuat/Online hanya relevan di halaman Kasir
    $('.topbar-cart-tabs').hidden = target !== 'cashier';
    // Panel geser "Pesanan Pelanggan" hanya ada di layar kasir
    const sliderHandle = $('#ordersSliderHandle');
    if (sliderHandle) sliderHandle.hidden = target !== 'cashier';
    if (target !== 'cashier') toggleOrdersSlider(false);
    closeSidebar();
    if (target === 'dashboard') renderDashboard();
    if (target === 'menu') renderMenuTable();
    if (target === 'reports') renderReports();
    if (target === 'settings') renderSnapshotList();
  }

  function openSidebar() {
    $('#posSidebar').classList.add('is-open');
    $('#sidebarOverlay').classList.add('is-visible');
    $('[data-action="open-sidebar"]').setAttribute('aria-expanded', 'true');
    $('#posSidebar').setAttribute('aria-hidden', 'false');
  }
  function closeSidebar() {
    $('#posSidebar').classList.remove('is-open');
    $('#sidebarOverlay').classList.remove('is-visible');
    $('[data-action="open-sidebar"]').setAttribute('aria-expanded', 'false');
    if (window.matchMedia('(max-width: 1180px)').matches) $('#posSidebar').setAttribute('aria-hidden', 'true');
    else $('#posSidebar').removeAttribute('aria-hidden');
  }

  // Sembunyikan/tampilkan sidebar di layar lebar. Pilihan diingat di storage,
  // jadi setelah refresh kasir tetap mendapat tampilan yang sama.
  function toggleSidebar() {
    state.sidebarHidden = !state.sidebarHidden;
    save(STORAGE_KEYS.sidebarHidden, state.sidebarHidden);
    applySidebarHidden();
  }

  function applySidebarHidden() {
    const hidden = !!state.sidebarHidden;
    const shell = $('#posShell');
    if (shell) shell.classList.toggle('is-sidebar-hidden', hidden);
    const button = $('[data-action="toggle-sidebar"]');
    if (!button) return;
    button.textContent = hidden ? '⇥' : '⇤';
    const label = hidden ? 'Tampilkan sidebar' : 'Sembunyikan sidebar';
    button.setAttribute('title', label);
    button.setAttribute('aria-label', label);
    button.setAttribute('aria-expanded', hidden ? 'false' : 'true');
  }

  function logout() {
    if (sessionLogoutTimer) window.clearTimeout(sessionLogoutTimer);
    sessionLogoutTimer = null;
    autoSnapshot('Cadangan sebelum logout');
    try { localStorage.removeItem(STORAGE_KEYS.session); } catch (error) { /* penyimpanan tidak tersedia */ }
    setApiToken(''); // token server tidak boleh tertinggal setelah keluar
    state.user = null;
    // Keranjang TIDAK dikosongkan: pesanan yang sedang dibayar (termasuk hasil
    // "Lanjutkan ke pembayaran" + menu tambahan) harus selamat lewat sesi berakhir.
    // Kasir berikutnya bisa tekan "Kosongkan" kalau itu bukan pesanannya.
    state.currentOrder = null;
    showLogin();
  }

  function checkSessionTimeout() {
    if (!state.user) return;
    const loginAt = Number(state.user.loginAt) || Date.now();
    let migrated = false;
    if (!state.user.loginDay) {
      state.user.loginDay = localDayKey(loginAt);
      migrated = true;
    }
    if (!Number.isFinite(Number(state.user.loginMinute))) {
      state.user.loginMinute = localMinuteOfDay(loginAt);
      migrated = true;
    }
    if (migrated) {
      save(STORAGE_KEYS.session, state.user);
    }
    const now = Date.now();
    const dateChanged = localDayKey(now) !== state.user.loginDay;
    const clockMovedBehindLogin = localMinuteOfDay(now) < Number(state.user.loginMinute);
    if (dateChanged || clockMovedBehindLogin) {
      logout();
      showToast('Sesi berakhir pukul 00.00 — silakan masuk kembali.');
    }
  }

  function localDayKey(timestamp) {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
  }

  function localMinuteOfDay(timestamp) {
    const date = new Date(timestamp);
    return date.getHours() * 60 + date.getMinutes();
  }

  function scheduleSessionLogout() {
    if (sessionLogoutTimer) window.clearTimeout(sessionLogoutTimer);
    if (!state.user) return;
    const now = Date.now();
    const nextMidnight = new Date(now);
    nextMidnight.setHours(24, 0, 0, 0);
    sessionLogoutTimer = window.setTimeout(checkSessionTimeout, Math.max(0, nextMidnight.getTime() - now));
  }

  function restoreSession() {
    const session = load(null, STORAGE_KEYS.session);
    if (session && session.name) {
      let migrated = false;
      if (!session.loginAt) { session.loginAt = Date.now(); migrated = true; }
      if (!session.loginDay) {
        session.loginDay = localDayKey(Number(session.loginAt));
        migrated = true;
      }
      if (!Number.isFinite(Number(session.loginMinute))) {
        session.loginMinute = localMinuteOfDay(Number(session.loginAt));
        migrated = true;
      }
      state.user = session;
      if (migrated) save(STORAGE_KEYS.session, state.user);
      if (localDayKey(Date.now()) !== session.loginDay || localMinuteOfDay(Date.now()) < Number(session.loginMinute)) {
        logout();
        showToast('Sesi berakhir pukul 00.00 — silakan masuk kembali.');
        return false;
      }
      scheduleSessionLogout();
      showApp();
      return true;
    }
    state.user = null;
    if (sessionLogoutTimer) window.clearTimeout(sessionLogoutTimer);
    sessionLogoutTimer = null;
    showLogin();
    return false;
  }

  function togglePassword() {
    const input = $('#loginPassword');
    const button = $('[data-action="toggle-password"]');
    const visible = input.type === 'text';
    input.type = visible ? 'password' : 'text';
    button.textContent = visible ? 'Lihat' : 'Sembunyikan';
  }

  function applyTheme(theme) {
    const dark = theme === 'dark';
    document.body.classList.toggle('is-dark', dark);
    const button = $('[data-action="toggle-theme"]');
    if (button) {
      button.textContent = dark ? '☾' : '☼';
      button.setAttribute('aria-label', dark ? 'Aktifkan mode terang' : 'Aktifkan mode gelap');
      button.title = dark ? 'Mode terang' : 'Mode gelap';
    }
  }

  function toggleTheme() {
    const next = document.body.classList.contains('is-dark') ? 'light' : 'dark';
    applyTheme(next);
    save(STORAGE_KEYS.theme, next);
  }

  function updateClock() {
    const now = new Date();
    $('#topbarDate').textContent = new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'short', year: 'numeric' }).format(now);
    $('#topbarTime').textContent = new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit' }).format(now);
  }

  function updateConnectionStatus() {
    const online = navigator.onLine;
    const pill = $('#connectionPill');
    pill.classList.toggle('is-offline', !online);
    $('#connectionText').textContent = online ? 'Shift aktif' : 'Mode offline';
    $('#offlineBanner').classList.toggle('is-visible', !online);
  }

  /* =========================================================================
     SINKRONISASI ANTAR-PERANGKAT (backend IPOS — lihat js/sync.js)
     ------------------------------------------------------------------------
     Prinsipnya tetap local-first: data lokal selalu yang dipakai kasir,
     sinkronisasi hanya menyalin perubahan ke database bersama dan menyatukan
     baris yang lebih baru dari perangkat lain. Semua terjadi di latar belakang;
     kalau mati/offline, POS tetap jalan persis seperti biasa.
     ========================================================================= */
  const SYNC_TABLE_BY_KEY = {
    [STORAGE_KEYS.products]: 'products',
    [STORAGE_KEYS.categories]: 'categories',
    [STORAGE_KEYS.settings]: 'settings',
    [STORAGE_KEYS.orders]: 'orders',
    [STORAGE_KEYS.pending]: 'pending_orders',
    [STORAGE_KEYS.online]: 'online_orders'
  };

  let applyingRemote = false; // penahan agar penerimaan baris remote tidak ikut dikirim ulang
  let remoteToastSeen = false;
  let syncStatusCache = { state: 'off', queued: 0, lastAt: '', error: '' };

  function syncEnabled() { return typeof MPJSync !== 'undefined'; }

  function currentSyncValue(key) {
    switch (key) {
      case STORAGE_KEYS.products: return state.products;
      case STORAGE_KEYS.categories: return state.categories;
      case STORAGE_KEYS.settings: return state.settings;
      case STORAGE_KEYS.orders: return state.orders;
      case STORAGE_KEYS.pending: return state.pendingOrders;
      case STORAGE_KEYS.online: return state.onlineOrders;
      default: return null;
    }
  }

  function syncKeyForTable(table) {
    return Object.keys(SYNC_TABLE_BY_KEY).find((key) => SYNC_TABLE_BY_KEY[key] === table) || null;
  }

  /* Daftar lengkap satu tabel -> baris [{id, payload}]. Untuk pengaturan
     (objek tunggal) dipakai id tetap 'main'. */
  function buildSyncEntries(key, value) {
    if (key === STORAGE_KEYS.settings) return value && typeof value === 'object' ? [{ id: 'main', payload: value }] : [];
    if (Array.isArray(value)) {
      return value
        .filter((item) => item && item.id !== undefined && item.id !== null)
        .map((item) => ({ id: String(item.id), payload: item }));
    }
    return [];
  }

  /* Dipanggil otomatis oleh save() setiap data tersimpan — menaruh baris ke
     antrean kirim di modul sync (tidak langsung jaringan, biar tidak memblokir).
     Dibungkus try/catch karena save() juga bisa berjalan saat skrip baru mulai
     (sebelum konstanta sync selesai dibaca) — sinkron boleh gagal, POS tidak. */
  // Katalog & pengaturan hanya boleh diubah pemilik. Kasir tetap mencatat
  // transaksi lewat tabel 'orders', jadi baris katalog TIDAK boleh diantrekan
  // saat yang masuk kasir — server akan menolaknya (403) dan antrean transaksi
  // bisa ikut macet.
  function canWriteTable(table) {
    if (table === 'products' || table === 'categories' || table === 'settings') {
      return Boolean(state.user && state.user.role === 'Pemilik');
    }
    return true;
  }

  function queueSync(key, value) {
    try {
      if (applyingRemote || !syncEnabled()) return;
      const table = SYNC_TABLE_BY_KEY[key];
      if (!table || !canWriteTable(table)) return;
      MPJSync.pushList(table, buildSyncEntries(key, value));
    } catch (error) {
      console.warn('Antrean sinkron gagal', error);
    }
  }

  /* Baris dari database disatukan ke data lokal (baris remote menang karena
     punya updated_at terbaru), lalu disimpan + dirender ulang. */
  function applyRemoteRows(table, rows) {
    if (!Array.isArray(rows) || !rows.length) return;
    const key = syncKeyForTable(table);
    if (!key) return;
    let changed = false;
    applyingRemote = true;
    try {
      if (table === 'settings') {
        // Identitas warung: nilai KOSONG dari cloud tidak boleh menghapus
        // isian lokal yang sudah diisi (mis. nomor telepon baru diketik lalu
        // tertimpa baris lama yang masih kosong). Isi lokal dipertahankan.
        const IDENTITY_KEYS = ['businessName', 'businessAddress', 'businessPhone'];
        rows.forEach((row) => {
          if (!row || row.deleted || !row.payload) return;
          const incoming = { ...row.payload };
          IDENTITY_KEYS.forEach((identityKey) => {
            const localValue = state.settings[identityKey];
            const remoteValue = incoming[identityKey];
            const remoteEmpty = remoteValue === '' || remoteValue === null || remoteValue === undefined;
            const localFilled = localValue !== '' && localValue !== null && localValue !== undefined;
            if (remoteEmpty && localFilled) incoming[identityKey] = localValue;
          });
          const merged = { ...state.settings, ...incoming };
          if (JSON.stringify(merged) === JSON.stringify(state.settings)) return; // sudah sama — jangan render ulang sia-sia
          state.settings = merged;
          changed = true;
        });
        if (changed) save(key, state.settings);
        if (!changed) return; // isi sudah sama — jangan render ulang
      } else {
        const current = currentSyncValue(key);
        const byId = new Map((Array.isArray(current) ? current : []).map((item) => [String(item.id), item]));
        rows.forEach((row) => {
          if (!row || row.id === undefined || row.id === null) return;
          const id = String(row.id);
          if (row.deleted || !row.payload) {
            if (byId.delete(id)) changed = true;
            return;
          }
          const existing = byId.get(id);
          if (!existing) { byId.set(id, row.payload); changed = true; }
          else if (JSON.stringify(existing) !== JSON.stringify(row.payload)) { byId.set(id, row.payload); changed = true; }
        });
        if (!changed) return;
        const merged = Array.from(byId.values());
        switch (table) {
          case 'products': state.products = merged; break;
          case 'categories': state.categories = normalizeCategories(merged); break;
          case 'orders': state.orders = normalizeOrders(merged); break;
          case 'pending_orders': state.pendingOrders = normalizePendingList(merged); break;
          case 'online_orders': state.onlineOrders = merged.map(normalizeOnlineOrder); break;
          default: return;
        }
        save(key, currentSyncValue(key));
      }
    } catch (error) {
      console.warn('Gagal menerapkan data sinkron', error);
      return;
    } finally {
      applyingRemote = false;
    }
    renderAll();
    // Toast hanya untuk baris dari PERANGKAT LAIN — baris kita sendiri yang
    // balik dari database bukan "pembaruan" dan tidak boleh menakuti kasir.
    if (isForeignRow(rows)) {
      if (!remoteToastSeen) {
        remoteToastSeen = true;
        showToast('Data diperbarui dari perangkat lain.');
      }
    }
  }

  function isForeignRow(rows) {
    if (!syncEnabled()) return false;
    let mine = null;
    try { mine = (MPJSync.status() || {}).deviceId || null; } catch (error) { mine = null; }
    return rows.some((row) => row && row.device_id && row.device_id !== mine);
  }

  /* Daftar lokal untuk bootstrap: saat database masih kosong (perangkat pertama
     menyambung), unggah isi lokal supaya perangkat berikutnya langsung dapat. */
  function localSyncEntries(table) {
    const key = syncKeyForTable(table);
    if (!key) return [];
    const value = currentSyncValue(key);
    return buildSyncEntries(key, value);
  }

  const SYNC_PILL_LABELS = {
    off: 'Lokal',
    disabled: 'Lokal',
    offline: 'Menunggu internet',
    busy: 'Sinkron…',
    queued: 'Menunggu kirim',
    error: 'Gagal sinkron',
    idle: 'Tersinkron'
  };
  const SYNC_SETTINGS_LABELS = {
    off: 'Mode lokal aktif',
    disabled: 'Sinkron dimatikan — mode lokal',
    offline: 'Menunggu koneksi internet',
    busy: 'Sinkron berjalan…',
    queued: 'Perubahan menunggu dikirim',
    error: 'Gagal sinkron — coba lagi',
    idle: 'Terhubung & tersinkron'
  };

  function renderSyncStatus(statusValue) {
    if (!statusValue || typeof statusValue !== 'object') return;
    syncStatusCache = statusValue;
    const stateName = statusValue.state || 'off';
    const pill = elSafe('#syncPill');
    const text = elSafe('#syncText');
    if (text) text.textContent = SYNC_PILL_LABELS[stateName] || 'Sinkron';
    if (pill) {
      pill.classList.toggle('is-synced', stateName === 'idle');
      pill.classList.toggle('is-busy', stateName === 'busy');
      pill.classList.toggle('is-queued', stateName === 'queued' || stateName === 'offline');
      pill.classList.toggle('is-offline', stateName === 'offline');
      pill.classList.toggle('is-error', stateName === 'error');
      const time = statusValue.lastAt ? new Date(statusValue.lastAt) : null;
      const timeLabel = time && !isNaN(time) ? ` · terakhir ${time.toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })}` : '';
      pill.title = `Sinkron antar-perangkat — tekan untuk sinkron sekarang${timeLabel}`;
    }
    const serverStatus = elSafe('#serverSyncStatus');
    if (serverStatus) serverStatus.textContent = SYNC_SETTINGS_LABELS[stateName] || 'Mode lokal aktif';
    const serverPill = elSafe('#serverSyncPill');
    if (serverPill) {
      serverPill.className = 'status-pill ' + (stateName === 'idle' ? 'available' : stateName === 'error' ? 'unavailable' : 'local');
      serverPill.textContent = ' ' + (stateName === 'idle' ? 'Terhubung' : stateName === 'error' ? 'Gagal' : stateName === 'off' || stateName === 'disabled' ? 'Lokal' : 'Sinkron');
    }
  }

  function runManualSync() {
    if (!syncEnabled()) { showToast('Modul sinkronisasi belum termuat.'); return; }
    let result;
    try { result = MPJSync.syncNow(); } catch (error) { showToast('Sinkronisasi gagal dijalankan.'); return; }
    Promise.resolve(result).then((ok) => {
      if (ok === false && navigator.onLine === false) showToast('Menunggu koneksi internet — perubahan sudah diantre.');
      else if (ok === false) showToast('Sinkronisasi sedang berjalan — coba lagi sebentar.');
      else showToast('Sinkronisasi selesai.');
    }).catch(() => showToast('Sinkronisasi gagal — coba lagi.'));
  }

  /* ======================================================================
     SERVER & PENGGUNA (sinkronisasi ke backend IPOS + Neon)
     Semua permintaan membawa token JWT hasil login. Tidak ada kredensial
     database di aplikasi ini — hanya token pengguna.
     ====================================================================== */
  async function apiRequest(path, options) {
    const base = apiBaseUrl();
    if (!base) throw new Error('Alamat server belum diatur.');
    const headers = Object.assign({ 'Content-Type': 'application/json' }, (options && options.headers) || {});
    const token = apiToken();
    if (token) headers.Authorization = 'Bearer ' + token;
    const res = await fetch(base + path, Object.assign({}, options, { headers }));
    let body = null;
    try { body = await res.json(); } catch (error) { body = null; }
    if (!res.ok) throw new Error((body && body.error) || ('Gagal menghubungi server (HTTP ' + res.status + ').'));
    return body;
  }

  function hydrateServerSettings() {
    const input = $('#apiBaseInput');
    if (input && !input.value) input.value = apiBaseUrl();
    const status = $('#apiConfigStatus');
    if (status) {
      status.textContent = apiBaseUrl()
        ? ('Alamat server tersimpan: ' + apiBaseUrl())
        : 'Belum diatur — aplikasi berjalan mode lokal (tanpa sinkronisasi antar-perangkat).';
    }
    const cred = $('#serverCredentialState');
    if (cred) {
      cred.textContent = apiBaseUrl()
        ? (apiToken() ? 'Sudah masuk ke server.' : 'Alamat diatur, tetapi belum masuk lewat server — keluar lalu masuk lagi untuk memakai server.')
        : 'Mode lokal.';
    }
  }

  function handleApiConfigSubmit(event) {
    event.preventDefault();
    const value = ($('#apiBaseInput') && $('#apiBaseInput').value || '').trim();
    try { if (window.MPJConfig) window.MPJConfig.setApiBase(value); } catch (error) { /* diabaikan */ }
    hydrateServerSettings();
    if (apiBaseUrl() && apiToken() && typeof MPJSync !== 'undefined' && MPJSync.syncNow) {
      try { MPJSync.syncNow(); } catch (error) { /* diabaikan */ }
    }
    showToast(value ? 'Alamat server disimpan.' : 'Alamat server dikosongkan — mode lokal.');
  }

  /* ---------- Pengguna: daftar akun + ubah nama/sandi ----------
     Sumber akun ada dua: server (kalau sudah masuk lewat server) atau
     perangkat ini (mode lokal). Bentuk barisnya sengaja sama supaya pemilik
     tidak perlu tahu bedanya. */
  let usersFromServer = null; // hasil GET /api/users (null = belum dimuat)
  let userEditKey = null;     // akun yang sedang diubah, format "<sumber>:<id>"

  function accountSource() {
    return (apiBaseUrl() && apiToken()) ? 'server' : 'lokal';
  }

  function accountSourceKey(source, id) {
    return source + ':' + String(id);
  }

  function splitUserKey(key) {
    const text = String(key || '');
    const cut = text.indexOf(':');
    if (cut < 0) return null;
    return { source: text.slice(0, cut), id: text.slice(cut + 1) };
  }

  function accountList(source) {
    if (source === 'server') return Array.isArray(usersFromServer) ? usersFromServer : [];
    return localUsers.map((user) => ({
      id: user.username,
      username: user.username,
      name: user.name,
      role: user.role,
      active: user.active !== false
    }));
  }

  function activeOwnerCount(excludeUsername) {
    return localUsers.filter((user) => user.role === 'Pemilik' && user.active !== false && user.username !== excludeUsername).length;
  }

  function openUsersPanel() {
    renderUsers();
    if (accountSource() === 'server') loadUsers();
  }

  function renderUsers() {
    const wrap = $('#userList');
    if (!wrap) return;
    const source = accountSource();
    const list = accountList(source);
    const hint = $('#userListSource');
    if (hint) {
      hint.textContent = source === 'server'
        ? 'Akun tersimpan di server. Tekan "Ubah" untuk mengganti nama atau sandi.'
        : 'Mode lokal: akun tersimpan di perangkat ini. Sandi bawaan 1234 — segera ganti lewat "Ubah".';
    }
    if (!list.length) {
      if (source === 'server' && usersFromServer === null) {
        wrap.innerHTML = '<p class="settings-hint">Daftar akun belum bisa dimuat dari server. Periksa alamat server dan sambungan internet, lalu tekan "Muat ulang".</p>';
        return;
      }
      wrap.innerHTML = source === 'server'
        ? '<p class="settings-hint">Belum ada akun di server. Tambahkan lewat formulir "Tambah pengguna".</p>'
        : '<p class="settings-hint">Belum ada akun.</p>';
      return;
    }
    wrap.innerHTML = list.map((user) => userRowMarkup(source, user)).join('');
  }

  function userRowMarkup(source, user) {
    const key = accountSourceKey(source, user.id);
    const active = user.active !== false;
    const isSelf = !!(state.user && state.user.username === user.username);
    const initial = escapeHtml(String(user.name || user.username || '?').charAt(0).toUpperCase());

    if (userEditKey === key) {
      const roles = ['Pemilik', 'Kasir'].map((role) =>
        `<option value="${role}"${user.role === role ? ' selected' : ''}>${role}</option>`).join('');
      return `<div class="user-row is-editing" data-user-key="${escapeAttr(key)}">
        <span class="integration-logo server">${initial}</span>
        <div class="user-edit">
          <label>Nama tampilan<input class="user-edit-name" type="text" maxlength="80" value="${escapeAttr(String(user.name || user.username))}" /></label>
          <label>Peran<select class="user-edit-role">${roles}</select></label>
          <label>Sandi baru<input class="user-edit-password" type="password" autocomplete="new-password" placeholder="kosongkan bila tidak diganti (min. 6)" /></label>
          <div class="button-row">
            <button class="primary-button tiny-button" type="button" data-action="user-save" data-user-key="${escapeAttr(key)}">Simpan</button>
            <button class="secondary-button tiny-button" type="button" data-action="user-edit-cancel">Batal</button>
          </div>
          <p class="settings-hint user-edit-status" hidden></p>
        </div>
      </div>`;
    }

    const badge = active
      ? '<span class="status-pill available">Aktif</span>'
      : '<span class="status-pill unavailable">Nonaktif</span>';
    const toggleButton = isSelf
      ? ''
      : `<button class="secondary-button tiny-button" type="button" data-action="user-toggle" data-user-key="${escapeAttr(key)}">${active ? '○ Nonaktifkan' : '◉ Aktifkan'}</button>`;
    const name = escapeHtml(String(user.name || user.username));
    const selfTag = isSelf ? ' <em class="user-self">· Anda</em>' : '';
    return `<div class="user-row${active ? '' : ' is-inactive'}" data-user-key="${escapeAttr(key)}">
      <span class="integration-logo server">${initial}</span>
      <div class="user-row-body"><strong>${name}${selfTag}</strong><small>${escapeHtml(user.username)} · ${escapeHtml(user.role)}</small></div>
      ${badge}
      <div class="user-row-actions">
        <button class="secondary-button tiny-button" type="button" data-action="user-edit" data-user-key="${escapeAttr(key)}">✎ Ubah</button>
        ${toggleButton}
      </div>
    </div>`;
  }

  function startUserEdit(key) {
    userEditKey = key || null;
    renderUsers();
    const input = $('.user-row.is-editing .user-edit-name');
    if (input) { input.focus(); if (input.select) input.select(); }
  }

  function cancelUserEdit() {
    userEditKey = null;
    renderUsers();
  }

  async function saveUser(button) {
    const parsed = splitUserKey(button && button.dataset.userKey);
    const row = button && button.closest('.user-row');
    if (!parsed || !row) return;
    const nameInput = row.querySelector('.user-edit-name');
    const roleInput = row.querySelector('.user-edit-role');
    const passwordInput = row.querySelector('.user-edit-password');
    const status = row.querySelector('.user-edit-status');
    const name = ((nameInput && nameInput.value) || '').trim();
    const role = roleInput && roleInput.value === 'Pemilik' ? 'Pemilik' : 'Kasir';
    const password = (passwordInput && passwordInput.value) || '';
    const fail = (message) => {
      if (status) { status.textContent = message; status.hidden = false; }
    };

    if (!name) return fail('Nama tampilan tidak boleh kosong.');
    if (password && password.length < 6) return fail('Sandi minimal 6 karakter.');

    if (parsed.source === 'lokal') {
      const user = findLocalUser(parsed.id);
      if (!user) return fail('Akun tidak ditemukan.');
      if (user.role === 'Pemilik' && role !== 'Pemilik' && user.active !== false && !activeOwnerCount(user.username)) {
        return fail('Harus ada minimal satu akun Pemilik yang aktif.');
      }
      user.name = name;
      user.role = role;
      if (password) user.password = password;
      saveLocalUsers();
      if (state.user && state.user.username === user.username) {
        state.user.name = user.name;
        state.user.role = user.role;
        save(STORAGE_KEYS.session, state.user);
        $('#userName').textContent = user.name;
        $('#userRole').textContent = user.role;
        $('#greetingName').textContent = user.name;
        $('#userAvatar').textContent = user.name.charAt(0).toUpperCase();
        applyRoleAccess();
      }
      userEditKey = null;
      renderUsers();
      showToast('Akun diperbarui.');
      return;
    }

    try {
      const body = { name, role };
      if (password) body.password = password;
      await apiRequest('/api/users/' + encodeURIComponent(parsed.id), { method: 'PATCH', body: JSON.stringify(body) });
      userEditKey = null;
      showToast('Akun diperbarui.');
      await loadUsers();
    } catch (error) {
      fail('Gagal menyimpan: ' + error.message);
    }
  }

  async function toggleUserActive(key) {
    const parsed = splitUserKey(key);
    if (!parsed) return;
    const user = accountList(parsed.source).find((item) => String(item.id) === String(parsed.id));
    if (!user) return;
    const activate = user.active === false;
    const isSelf = !!(state.user && state.user.username === user.username);

    if (!activate && isSelf) {
      showToast('Tidak bisa menonaktifkan akun yang sedang dipakai.');
      return;
    }
    if (parsed.source === 'lokal' && !activate && user.role === 'Pemilik' && !activeOwnerCount(user.username)) {
      showToast('Harus ada minimal satu akun Pemilik yang aktif.');
      return;
    }
    const label = user.name || user.username;
    if (!window.confirm(activate ? `Aktifkan kembali akun ${label}?` : `Nonaktifkan akun ${label}? Akun tidak bisa masuk sampai diaktifkan lagi.`)) return;

    if (parsed.source === 'lokal') {
      const target = findLocalUser(user.username);
      if (!target) return;
      target.active = activate;
      saveLocalUsers();
      renderUsers();
      showToast(activate ? 'Akun diaktifkan.' : 'Akun dinonaktifkan.');
      return;
    }

    try {
      await apiRequest('/api/users/' + encodeURIComponent(parsed.id), { method: 'PATCH', body: JSON.stringify({ active: activate }) });
      showToast(activate ? 'Akun diaktifkan.' : 'Akun dinonaktifkan.');
      await loadUsers();
    } catch (error) {
      showToast('Gagal: ' + error.message);
    }
  }

  async function loadUsers() {
    const status = $('#userListStatus');
    if (accountSource() !== 'server') {
      renderUsers();
      return;
    }
    try {
      const body = await apiRequest('/api/users');
      usersFromServer = Array.isArray(body && body.users) ? body.users : [];
      if (status) status.textContent = `${usersFromServer.length} akun dimuat dari server.`;
      renderUsers();
    } catch (error) {
      usersFromServer = null;
      if (status) status.textContent = 'Gagal memuat daftar akun dari server: ' + error.message;
      renderUsers();
    }
  }

  async function handleUserFormSubmit(event) {
    event.preventDefault();
    const status = $('#userFormStatus');
    const setStatus = (text) => { if (status) status.textContent = text; };
    const username = ((($('#newUserUsername') || {}).value) || '').trim().toLowerCase();
    const name = ((($('#newUserDisplay') || {}).value) || '').trim();
    const role = $('#newUserRole') && $('#newUserRole').value === 'Pemilik' ? 'Pemilik' : 'Kasir';
    const password = (($('#newUserPassword') || {}).value) || '';

    if (!/^[a-z0-9._-]{3,60}$/.test(username)) return setStatus('Nama pengguna: huruf kecil, angka, titik, garis bawah, strip (3-60 karakter).');
    if (!name) return setStatus('Nama tampilan tidak boleh kosong.');
    if (password.length < 6) return setStatus('Sandi minimal 6 karakter.');

    if (accountSource() === 'lokal') {
      if (findLocalUser(username)) return setStatus('Nama pengguna itu sudah dipakai.');
      localUsers.push({ username, name, role, active: true, password });
      saveLocalUsers();
      event.target.reset();
      userEditKey = null;
      setStatus(`Akun ${username} ditambahkan.`);
      showToast('Pengguna ditambahkan.');
      renderUsers();
      return;
    }

    try {
      await apiRequest('/api/users', {
        method: 'POST',
        body: JSON.stringify({ username, name, role, password })
      });
      event.target.reset();
      setStatus('Pengguna ditambahkan.');
      showToast('Pengguna ditambahkan.');
      await loadUsers();
    } catch (error) {
      setStatus('Gagal menambah pengguna: ' + error.message);
    }
  }

  function startSync() {
    if (!syncEnabled()) { renderSyncStatus({ state: 'off', queued: 0 }); return; }
    try {
      MPJSync.init({ onRows: applyRemoteRows, onStatus: renderSyncStatus, getEntries: localSyncEntries });
      Promise.resolve(MPJSync.start()).catch((error) => console.warn('Sinkron tidak bisa dimulai', error));
    } catch (error) {
      console.warn('Sinkron tidak bisa dimulai', error);
    }
  }

  function updateBusinessLabels() {
    const name = state.settings.businessName || 'Mie Pangsit Jakarta';
    $('#sidebarStoreName').textContent = name;
    $('.store-status-card').title = name;
  }

  function hydrateSettingsForm() {
    $('#businessName').value = state.settings.businessName || '';
    $('#businessAddress').value = state.settings.businessAddress || '';
    $('#businessPhone').value = state.settings.businessPhone || '';
    hydrateServerSettings();
    hydrateQrisStatus();
    renderUsers(); // daftar akun (mode lokal langsung; mode server dimuat saat tab dibuka)
    renderSyncStatus(syncStatusCache); // status sinkron mengikuti modul sinkron, bukan bendera statis
    const footerInput = $('#receiptFooterInput');
    if (footerInput) footerInput.value = state.settings.receiptFooter || '';
    const rejectionInput = $('#onlineRejectionMessageInput');
    if (rejectionInput) rejectionInput.value = state.settings.onlineRejectionMessage || '';
    const modelSelect = $('#printerModel');
    if (modelSelect) modelSelect.value = state.settings.printerModel || 'generic';
    const deviceSelect = $('#printerDevice');
    if (deviceSelect) {
      deviceSelect.innerHTML = `<option value="">— pilih perangkat yang sudah dipasangkan —</option>`;
      const address = state.settings.printerAddress || '';
      const storedName = state.settings.printerDeviceName || '';
      if (address && storedName) {
        const option = document.createElement('option');
        option.value = address;
        option.textContent = storedName;
        deviceSelect.appendChild(option);
        deviceSelect.value = address;
      }
    }
    renderPrinterStatus();
  }

  function handleReceiptFooterSubmit(event) {
    event.preventDefault();
    state.settings.receiptFooter = $('#receiptFooterInput').value.replace(/\r/g, '').trim();
    state.settings.onlineRejectionMessage = ($('#onlineRejectionMessageInput').value || '').replace(/\r/g, '').trim() || DEFAULT_SETTINGS.onlineRejectionMessage;
    save(STORAGE_KEYS.settings, state.settings);
    $('#onlineRejectionMessageInput').value = state.settings.onlineRejectionMessage;
    showToast('Tulisan struk dan penolakan berhasil disimpan.');
  }

  function handlePrinterModelChange(event) {
    state.settings.printerModel = event.target.value;
    save(STORAGE_KEYS.settings, state.settings);
    renderPrinterStatus();
    showToast('Model printer disetel.');
  }

  function handlePrinterDeviceChange(event) {
    const address = event.target.value;
    const selected = event.target.selectedOptions[0];
    state.settings.printerAddress = address;
    state.settings.printerDeviceName = address && selected ? (selected.textContent || address) : '';
    save(STORAGE_KEYS.settings, state.settings);
    renderPrinterStatus();
    showToast(address ? 'Printer Bluetooth dipilih.' : 'Printer Bluetooth dilepas.');
  }

  function renderPrinterStatus() {
    const status = $('#btPrinterStatus');
    if (!status) return;
    const configured = state.settings.printerModel && state.settings.printerAddress;
    if (configured) {
      const modelLabel = { x58bt: 'iware X58BT II', mp58: 'MP58', generic: 'Printer 58 mm umum' }[state.settings.printerModel] || 'Printer 58 mm';
      status.textContent = `Siap pakai — ${modelLabel} (${state.settings.printerDeviceName || state.settings.printerAddress}). Tekan "Test cetak" untuk mencoba.`;
      status.classList.remove('is-err');
      status.classList.add('is-ok');
    } else {
      status.textContent = 'Belum diatur — pilih model dan perangkat Bluetooth di atas.';
      status.classList.remove('is-ok');
      status.classList.add('is-err');
    }
  }

  function handleBusinessSubmit(event) {
    event.preventDefault();
    state.settings.businessName = $('#businessName').value.trim() || DEFAULT_SETTINGS.businessName;
    state.settings.businessAddress = $('#businessAddress').value.trim();
    state.settings.businessPhone = $('#businessPhone').value.trim();
    save(STORAGE_KEYS.settings, state.settings);
    updateBusinessLabels();
    showToast('Identitas warung berhasil disimpan.');
  }

  function qrisSafe(fn, fallback = null) {
    try {
      const result = fn();
      return result === undefined ? fallback : result;
    } catch (error) {
      console.warn('QRIS:', error.message);
      return fallback;
    }
  }

  function qrisPayload() {
    return (state.settings.qrisStaticPayload || '').trim();
  }

  function hydrateQrisStatus() {
    const payload = qrisPayload();
    const textarea = $('#qrisStaticPayload');
    const preview = $('#qrisMerchantPreview');
    const status = $('#qrisStatus');
    const pill = $('#qrisStatusPill');
    if (textarea) textarea.value = payload;
    if (preview) preview.value = payload ? (qrisSafe(() => QRIS.parseQRIS(payload).merchantName, '') || 'Nama merchant tidak terbaca') : '';
    if (status) status.textContent = payload ? 'Siap dipakai (dinamis)' : 'Belum diatur';
    if (pill) {
      pill.textContent = payload ? 'Siap' : 'Perlu QRIS';
      pill.classList.toggle('pending', !payload);
      pill.classList.toggle('available', !!payload);
    }
  }

  function handleQrisSubmit(event) {
    event.preventDefault();
    const payload = $('#qrisStaticPayload').value.trim();
    const errorBox = $('#qrisFormError');
    const clearError = () => { errorBox.hidden = true; errorBox.textContent = ''; };
    if (!payload) {
      state.settings.qrisStaticPayload = '';
      save(STORAGE_KEYS.settings, state.settings);
      hydrateQrisStatus();
      clearError();
      showToast('String QRIS statis dikosongkan.');
      return;
    }
    const validation = QRIS.validateQRIS(payload);
    if (!validation.valid) {
      errorBox.textContent = `QRIS tidak valid: ${validation.errors.join(' · ')}`;
      errorBox.hidden = false;
      return;
    }
    state.settings.qrisStaticPayload = payload;
    save(STORAGE_KEYS.settings, state.settings);
    hydrateQrisStatus();
    clearError();
    const merchant = qrisSafe(() => QRIS.parseQRIS(payload).merchantName, '');
    showToast(merchant ? `QRIS tersimpan — ${merchant}. Kasir siap membuat QRIS dinamis.` : 'QRIS statis tersimpan. Kasir siap membuat QRIS dinamis.');
  }

  /* ---------- Baca QRIS dari foto ----------
     Pemilik biasanya hanya punya gambar/foto QRIS, bukan teks panjangnya.
     Foto dibaca di perangkat dengan decoder QR lokal (jsQR) — tanpa internet
     dan tanpa mengirim gambar ke server mana pun. */
  function handleQrisImageUpload(event) {
    const input = event.target;
    const file = input.files && input.files[0];
    input.value = ''; // supaya foto yang sama bisa dipilih ulang
    if (!file) return;
    const statusEl = $('#qrisUploadStatus');
    const setStatus = (text) => { if (statusEl) statusEl.textContent = text; };
    if (file.size > 12 * 1024 * 1024) {
      setStatus('Foto terlalu besar (maksimal 12 MB). Coba foto lain.');
      showToast('Foto terlalu besar — maksimal 12 MB.');
      return;
    }
    setStatus('Membaca QR dari foto…');
    decodeQrFromImage(file).then((text) => {
      const payload = String(text || '').trim();
      if (!payload) {
        setStatus('QR tidak terbaca. Pastikan seluruh QR terlihat, tajam, dan tidak silau.');
        showToast('QR tidak terbaca dari foto itu. Coba foto yang lebih jelas.');
        return;
      }
      const textarea = $('#qrisStaticPayload');
      const validation = QRIS.validateQRIS(payload);
      if (!validation.valid) {
        // Rincian teknis hanya untuk console; pemilik cukup pesan singkat.
        console.warn('QR bukan QRIS:', validation.errors);
        setStatus('QR terbaca, tetapi itu bukan kode QRIS. Pakai foto QRIS dari bank/e-wallet (ada logo QRIS).');
        showToast('QR itu bukan QRIS. Coba foto QRIS yang ada logo QRIS-nya.');
        return;
      }
      if (textarea) textarea.value = payload;
      const merchant = qrisSafe(() => QRIS.parseQRIS(payload).merchantName, '');
      setStatus(merchant
        ? `QRIS terbaca — ${merchant}. Tekan "Simpan QRIS" untuk menyimpan.`
        : 'QRIS terbaca. Tekan "Simpan QRIS" untuk menyimpan.');
      showToast(merchant ? `QRIS terbaca — ${merchant}.` : 'QRIS terbaca dari foto.');
    }).catch((error) => {
      console.warn('QRIS upload:', error);
      setStatus('Foto tidak bisa dibaca. Coba file JPG/PNG lain.');
      showToast('Foto tidak bisa dibaca.');
    });
  }

  function decodeQrFromImage(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        try {
          const decoder = typeof jsQR === 'function' ? jsQR : (window.jsQR && window.jsQR.default);
          if (typeof decoder !== 'function') {
            URL.revokeObjectURL(url);
            reject(new Error('Pembaca QR tidak tersedia.'));
            return;
          }
          const canvas = document.createElement('canvas');
          const ctx = canvas.getContext('2d', { willReadFrequently: true });
          const sourceWidth = img.naturalWidth || img.width;
          const sourceHeight = img.naturalHeight || img.height;
          const longest = Math.max(sourceWidth, sourceHeight);
          // Coba beberapa ukuran: QRIS di foto HP bisa sangat besar atau kecil.
          const sizes = [1600, 2400, 900]
            .map((size) => Math.min(size, longest))
            .filter((size, index, arr) => size > 0 && arr.indexOf(size) === index);
          let found = '';
          for (let index = 0; index < sizes.length && !found; index += 1) {
            const size = sizes[index];
            const ratio = size / longest;
            const width = Math.max(1, Math.round(sourceWidth * ratio));
            const height = Math.max(1, Math.round(sourceHeight * ratio));
            canvas.width = width;
            canvas.height = height;
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(img, 0, 0, width, height);
            const pixels = ctx.getImageData(0, 0, width, height);
            const result = decoder(pixels.data, width, height, { inversionAttempts: 'attemptBoth' });
            if (result && result.data) found = result.data;
          }
          URL.revokeObjectURL(url);
          resolve(found);
        } catch (error) {
          URL.revokeObjectURL(url);
          reject(error);
        }
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error('Foto tidak bisa dibuka.'));
      };
      img.src = url;
    });
  }

  function formatRupiah(value) {
    return new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value) || 0).replace(/\s/g, ' ');
  }

  function formatNumber(value) {
    return new Intl.NumberFormat('id-ID', { maximumFractionDigits: 2 }).format(Number(value) || 0);
  }

  function formatRupiahShort(value) {
    const amount = Math.round(Math.abs(Number(value) || 0));
    if (amount >= 1000000) return `${(amount / 1000000).toFixed(amount % 1000000 === 0 ? 0 : 1).replace('.', ',')} jt`;
    if (amount >= 1000) return `${Math.round(amount / 1000)} rb`;
    return formatNumber(amount);
  }

  function dateKey(date = new Date()) {
    if (!Number.isFinite(date.getTime())) return '';
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  // Tanggal rusak (impor manual, storage penuh) tidak boleh membuat Intl melempar
  // RangeError dan mengosongkan seluruh daftar
  function safeDate(value) {
    const date = value instanceof Date ? value : new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function orderDate(order) { return dateKey(new Date(order.createdAt)); }

  function ordersForDate(key) { return state.orders.filter((order) => orderDate(order) === key); }

  function renderDashboard() {
    const orders = ordersForDate(dateKey());
    const revenue = orders.reduce((sum, order) => sum + order.total, 0);
    const itemCount = orders.reduce((sum, order) => sum + orderItems(order).reduce((itemSum, item) => itemSum + item.qty, 0), 0);
    $('#statRevenue').textContent = formatRupiah(revenue);
    $('#statRevenueHint').textContent = `${orders.length} transaksi selesai`;
    $('#statOrders').textContent = orders.length;
    $('#statAverage').textContent = formatRupiah(orders.length ? revenue / orders.length : 0);
    $('#statItems').textContent = itemCount;
    const recent = [...orders].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 6);
    const itemSummary = (order) => orderItems(order).map((item) => `${item.qty}× ${item.name}`).join(', ');
    $('#recentOrders').innerHTML = recent.length ? recent.map((order) => {
      const items = itemSummary(order);
      return `<tr><td data-label="Waktu">${escapeHtml(formatTime(order.createdAt))}</td><td data-label="No. transaksi"><span class="order-number">${escapeHtml(order.id)}</span></td><td data-label="Pesanan" title="${escapeHtml(items)}">${escapeHtml(items)}</td><td data-label="Pembayaran"><span class="payment-badge ${escapeHtml(order.payment)}">${paymentLabel(order.payment)}</span></td><td data-label="Total" class="align-right"><strong>${formatRupiah(order.total)}</strong></td><td data-label="Struk" class="align-right"><button class="row-action" type="button" data-action="reprint-order" data-order-id="${escapeHtml(order.id)}" title="Cetak ulang struk ${escapeHtml(order.id)}" aria-label="Cetak ulang struk ${escapeHtml(order.id)}">▤</button></td></tr>`;
    }).join('') : '<tr><td colspan="6" class="empty-cell">Belum ada transaksi hari ini.</td></tr>';
  }

  function renderProducts() {
    const query = state.search;
    let hasHidden = false;
    const products = state.products.filter((product) => {
      // Menu yang dinonaktifkan di halaman Menu disembunyikan di kasir
      if (product.available === false) { hasHidden = true; return false; }
      const categoryMatch = state.category === 'semua' || product.category === state.category;
      const searchMatch = !query || `${product.name} ${product.description}`.toLowerCase().includes(query);
      return categoryMatch && searchMatch;
    });
    $('#productGrid').innerHTML = products.length ? products.map((product) => {
      const available = isProductAvailable(product);
      return `<button class="product-card" type="button" data-add-product="${escapeAttr(product.id)}" ${available ? '' : 'disabled'}>
        <span class="product-emoji">${product.emoji || '🍽️'}</span>
        <span class="product-name"><strong>${escapeHtml(product.name)}</strong></span>
        <span class="product-price">${formatRupiah(unitPrice(product))}</span>
      </button>`;
    }).join('') : `<div class="empty-cell" style="grid-column:1/-1">${hasHidden ? 'Menu yang dinonaktifkan disembunyikan di kasir.' : 'Menu tidak ditemukan.'}</div>`;
  }

  function getProductAvailability(product, ignoreCart = false) {
    const hasStockLimit = product && product.stock !== null && product.stock !== undefined && Number.isFinite(Number(product.stock));
    const stock = hasStockLimit ? Number(product.stock) : null;
    const inCart = ignoreCart ? 0 : state.cart.find((item) => item.productId === product.id)?.qty || 0;
    if (!product || !product.available) return { canSell: false, statusLabel: 'Nonaktif', statusClass: 'unavailable', stock };
    if (hasStockLimit && stock <= 0) return { canSell: false, statusLabel: 'Habis', statusClass: 'unavailable', stock };
    if (hasStockLimit && inCart >= stock) return { canSell: false, statusLabel: 'Batas stok tercapai', statusClass: 'pending', stock };
    if (hasStockLimit && stock <= 3) return { canSell: true, statusLabel: 'Stok menipis', statusClass: 'pending', stock };
    return { canSell: true, statusLabel: 'Tersedia', statusClass: 'available', stock };
  }

  function isProductAvailable(product) {
    return getProductAvailability(product).canSell;
  }

  function addToCart(productId) {
    const product = state.products.find((item) => item.id === productId);
    if (!product || !isProductAvailable(product)) {
      showToast('Menu ini sedang tidak tersedia.');
      return false;
    }
    const existing = state.cart.find((item) => item.productId === productId);
    // nama & harga ikut disimpan sebagai cadangan: kalau menunya diubah/dihapus,
    // isi keranjang & total TIDAK berubah diam-diam
    if (existing) {
      existing.qty += 1;
      existing.name = product.name;
      existing.price = unitPrice(product);
      existing.emoji = product.emoji || '';
    } else {
      state.cart.push({ productId, qty: 1, name: product.name, price: unitPrice(product), emoji: product.emoji || '', note: '' });
    }
    renderProducts();
    renderCart();
    return true;
  }

  function changeCartQuantity(productId, change) {
    const item = state.cart.find((cartItem) => cartItem.productId === productId);
    if (!item) return;
    const product = state.products.find((menuItem) => menuItem.id === productId);
    if (change > 0 && !product) {
      showToast('Menu ini sudah tidak ada di daftar menu — kurangi atau hapus dari keranjang.', 6000);
      return;
    }
    const hasStockLimit = product && product.stock !== null && product.stock !== undefined && Number.isFinite(Number(product.stock));
    if (change > 0 && product && !product.available) {
      showToast(`${product.name} sedang dinonaktifkan.`);
      return;
    }
    if (change > 0 && hasStockLimit && item.qty + change > Number(product.stock)) {
      showToast(`Stok ${product.name} hanya ${product.stock}.`);
      return;
    }
    item.qty += change;
    if (item.qty <= 0) state.cart = state.cart.filter((cartItem) => cartItem.productId !== productId);
    renderProducts();
    renderCart();
  }

  /* Catatan per menu di keranjang: ketuk barisnya untuk membuka kotak catatan.
     Simpan langsung ke state + storage agar ikut tersimpan saat checkout/hold,
     tanpa merender ulang tiap ketukan (fokus input tetap dipertahankan). */
  function toggleCartNote(productId) {
    state.cartNoteOpenId = state.cartNoteOpenId === productId ? null : productId;
    renderCart();
  }

  function handleDocumentInput(event) {
    const input = event.target.closest ? event.target.closest('[data-item-note-input]') : null;
    if (!input) return;
    const item = state.cart.find((cartItem) => cartItem.productId === input.dataset.itemNoteInput);
    if (!item) return;
    item.note = String(input.value || '').trim().slice(0, 120);
    saveCart();
  }

  function unitPrice(product) {
    return product ? (Number(product.price) || 0) : 0;
  }

  function cartItemProduct(item) {
    return state.products.find((menuItem) => menuItem.id === item.productId) || null;
  }

  function cartItemMissing(item) {
    return !cartItemProduct(item);
  }

  function cartItemPrice(item) {
    const product = cartItemProduct(item);
    if (product) return unitPrice(product);
    return Math.max(0, Number(item.price) || 0); // harga saat ditambahkan ke keranjang
  }

  function cartItemName(item) {
    const product = cartItemProduct(item);
    return product ? product.name : (item.name || 'Menu tidak ada');
  }

  function cartItemEmoji(item) {
    const product = cartItemProduct(item);
    return (product && product.emoji) || item.emoji || '🍽️';
  }

  function cartTotals() {
    const subtotal = state.cart.reduce((sum, item) => sum + cartItemPrice(item) * item.qty, 0);
    const discount = Math.min(Math.max(Number($('#discountInput')?.value || 0), 0), subtotal);
    return { subtotal, discount, total: Math.max(0, subtotal - discount) };
  }

  function renderCart() {
    const count = state.cart.reduce((sum, item) => sum + item.qty, 0);
    $('#cartCount').textContent = count;
    const sliderBadge = $('#ordersSliderCartBadge');
    if (sliderBadge) { sliderBadge.textContent = count; sliderBadge.hidden = !count; }
    if (!state.cart.length) {
      $('#cartItems').innerHTML = '<div class="empty-cart"><span>🛒</span><strong>Keranjang masih kosong</strong><small>Pilih menu di layar kasir untuk memulai.</small></div>';
    } else {
      $('#cartItems').innerHTML = state.cart.map((item) => {
        const missing = cartItemMissing(item);
        const unit = cartItemPrice(item);
        const name = cartItemName(item);
        const itemNote = String(item.note || '').trim();
        const noteOpen = state.cartNoteOpenId === item.productId;
        const sub = missing
          ? '<small>⚠ menu sudah tidak ada di daftar menu — hapus dari keranjang</small>'
          : `<small>${formatRupiah(unit)} / item${itemNote ? ` · 📝 ${escapeHtml(itemNote)}` : ''}</small>`;
        return `<div class="cart-item${missing ? ' is-orphan' : ''}${noteOpen ? ' is-note-open' : ''}" data-cart-item-note="${escapeAttr(item.productId)}" title="Ketuk untuk ${noteOpen ? 'menutup' : 'menambah'} catatan menu">
          <span class="cart-item-emoji">${cartItemEmoji(item)}</span>
          <span class="cart-item-copy"><strong>${escapeHtml(name)}</strong>${sub}</span>
          <span class="cart-item-actions"><button type="button" data-quantity-action="-1" data-product-id="${escapeAttr(item.productId)}" aria-label="Kurangi ${escapeHtml(name)}">−</button><span class="cart-qty">${item.qty}</span><button type="button" data-quantity-action="1" data-product-id="${escapeAttr(item.productId)}" aria-label="Tambah ${escapeHtml(name)}" ${missing ? 'disabled' : ''}>+</button></span>
          <span class="cart-item-total">${formatRupiah(unit * item.qty)}</span>
          <div class="cart-item-note"><input data-item-note-input="${escapeAttr(item.productId)}" type="text" maxlength="120" placeholder="Catatan untuk ${escapeHtml(name)}: mis. pedas, tanpa bawang…" value="${escapeAttr(itemNote)}" aria-label="Catatan untuk ${escapeHtml(name)}" /></div>
        </div>`;
      }).join('');
    }
    const totals = cartTotals();
    $('#cartSubtotal').textContent = formatRupiah(totals.subtotal);
    $('#cartTotal').textContent = formatRupiah(totals.total);
    $('#checkoutButton').disabled = !state.cart.length;
    const holdButton = $('#holdOrderButton');
    if (holdButton) holdButton.disabled = !state.cart.length;
    saveCart(); // keranjang selalu tersimpan: refresh/tutup aplikasi tidak menghapus pesanan
    updateQueueBadges();
  }

  function clearCart() {
    state.cart = [];
    $('#discountInput').value = '0';
    const noteInput = $('#cartNoteInput');
    if (noteInput) noteInput.value = '';
    renderProducts();
    renderCart();
  }

  /* Keranjang ikut ditulis ke storage setiap berubah (fungsinya satu jalan:
     semua perubahan keranjang selalu lewat renderCart). Jadi walau aplikasi
     ditutup/refresh di tengah pembayaran, pesanan tinggal dilanjutkan —
     tidak kembali jadi "Simpan, bayar nanti" dan tidak hilang. */
  function loadCartData() {
    const raw = load(null, STORAGE_KEYS.cartData);
    if (!raw || typeof raw !== 'object') return { items: [], discount: 0, orderType: 'dine-in', tableNumber: '', note: '' };
    const items = (Array.isArray(raw.items) ? raw.items : []).map((item) => {
      if (!item || typeof item !== 'object' || !item.productId) return null;
      const qty = Math.max(1, Math.floor(Number(item.qty) || 1));
      const price = Math.max(0, Number(item.price) || 0);
      return {
        productId: String(item.productId),
        qty,
        name: String(item.name || ''),
        price,
        emoji: String(item.emoji || ''),
        note: String(item.note || '').slice(0, 120)
      };
    }).filter(Boolean);
    return {
      items,
      discount: Math.max(0, Number(raw.discount) || 0),
      orderType: raw.orderType === 'takeaway' ? 'takeaway' : 'dine-in',
      tableNumber: String(raw.tableNumber || ''),
      note: String(raw.note || '').slice(0, 120)
    };
  }

  function saveCart() {
    const discountInput = $('#discountInput');
    const tableInput = $('#tableNumber');
    return save(STORAGE_KEYS.cartData, {
      items: state.cart,
      discount: Math.max(0, Number(discountInput ? discountInput.value : 0) || 0),
      orderType: state.orderType,
      tableNumber: tableInput ? String(tableInput.value || '').trim() : '',
      note: ($('#cartNoteInput')?.value || '').trim().slice(0, 120)
    });
  }

  function applyOrderTypeUI() {
    $$('#orderTypeTabs button').forEach((button) => {
      const active = button.dataset.orderType === state.orderType;
      button.classList.toggle('is-active', active);
      button.setAttribute('aria-pressed', String(active));
    });
    const field = $('#tableField');
    if (field) field.classList.toggle('is-visible', state.orderType === 'dine-in');
  }

  // Tombol di layar pembayaran: kembali ke keranjang untuk menambah menu.
  // Keranjang dan semua isinya tetap tersimpan — tidak balik ke "Simpan, bayar nanti".
  function addMoreItems() {
    closeModal();
    switchCartTab('cart');
    navigate('cashier');
    toggleOrdersSlider(false); // menu kembali full satu layar untuk menambah menu
    showToast('Silakan tambah menu, lalu tekan "Proses pembayaran". Isi keranjang tetap tersimpan.');
  }

  function openCheckout(options = {}) {
    if (!state.cart.length) return;
    const totals = cartTotals();
    $('#modalTotal').textContent = formatRupiah(totals.total);
    $('#modalItemCount').textContent = `${state.cart.reduce((sum, item) => sum + item.qty, 0)} item`;
    if (!options.keepCashReceived) $('#cashReceived').value = '';
    renderChange();
    if (!options.keepPayment) selectPayment('cash');
    else if (state.selectedPayment === 'qris') selectPayment('qris');
    openModal('checkoutModal');
    // Buka modal dulu baru scroll — elemen harus terlihat agar scrollIntoView bekerja
    if (state.selectedPayment === 'qris' && qrisPayload()) scrollQrisDisplay();
  }

  function selectPayment(payment) {
    state.selectedPayment = payment;
    $$('.payment-option').forEach((option) => {
      const active = option.dataset.payment === payment;
      option.classList.toggle('is-active', active);
      option.setAttribute('aria-pressed', String(active));
    });
    $('#cashPaymentFields').hidden = payment !== 'cash';
    hideQrisDisplay();
    const note = $('#paymentNote');
    if (payment === 'qris') {
      if (qrisPayload()) {
        note.hidden = true;
        note.textContent = '';
        renderQrisDisplay();
        scrollQrisDisplay(); // tombol QRIS ditekan -> langsung tampilkan QR-nya
      } else {
        note.hidden = false;
        note.textContent = 'QRIS belum diatur. Masukkan string QRIS statis warung di Pengaturan → Pembayaran QRIS. Untuk sekarang, transaksi dicatat setelah kasir menekan selesai (mode simulasi).';
      }
    } else if (payment === 'transfer') {
      note.hidden = false;
      note.textContent = 'Pastikan transfer sudah diterima sebelum menyelesaikan transaksi.';
    } else if (payment === 'card') {
      note.hidden = false;
      note.textContent = 'Pastikan uang sudah diterima sebelum menyelesaikan transaksi.';
    } else {
      note.hidden = true;
      note.textContent = '';
    }
    const qrisReady = !!qrisPayload();
    $('#completePayment').innerHTML = payment === 'qris' && !qrisReady ? 'Simulasikan QRIS dibayar <span>→</span>' : 'Selesaikan transaksi <span>→</span>';
  }

  function hideQrisDisplay() {
    const area = $('#qrisDisplay');
    if (area) area.hidden = true;
  }

  /* QRIS muncul di bawah pilihan pembayaran; di layar kecil tombol-tombol
     lain menutupinya. Setelah QR ditekan, gulir modal agar QRIS terlihat.
     Pakai scroll instan: animasi smooth bisa tertahan bila frame renderer
     lagi tidak jalan (mis. WebView hemat baterai) sehingga scroll batal. */
  function scrollQrisDisplay() {
    const area = $('#qrisDisplay');
    if (!area || area.hidden || typeof area.scrollIntoView !== 'function') return;
    area.scrollIntoView({ block: 'center' });
  }

  function renderQrisDisplay() {
    const area = $('#qrisDisplay');
    if (!area) return;
    const payload = qrisPayload();
    if (!payload) {
      hideQrisDisplay();
      return;
    }
    const totals = cartTotals();
    let dynamic;
    try {
      dynamic = QRIS.convertQRIS(payload, { amount: totals.total });
    } catch (error) {
      const note = $('#paymentNote');
      if (note) {
        note.hidden = false;
        note.textContent = `QRIS gagal dibuat: ${error.message}`;
      }
      hideQrisDisplay();
      return;
    }
    let parsed = qrisSafe(() => QRIS.parseQRIS(dynamic), null);
    if (!parsed || !parsed.merchantName) parsed = qrisSafe(() => QRIS.parseQRIS(payload), null);
    const merchant = (parsed && parsed.merchantName) || state.settings.businessName || 'Warung';
    $('#qrisMerchantLabel').textContent = merchant;
    $('#qrisAmountLabel').textContent = formatRupiah(totals.total);
    const wrap = $('#qrisQr');
    if (wrap) {
      wrap.innerHTML = '';
      try {
        const qr = qrcode(0, 'M');
        qr.addData(dynamic);
        qr.make();
        if (typeof qr.createSvgTag === 'function') {
          wrap.innerHTML = qr.createSvgTag({ cellSize: 5, margin: 4, scalable: true, alt: 'QRIS pembayaran' });
        } else {
          const img = document.createElement('img');
          img.src = qr.createDataURL(8, 4);
          img.alt = 'QRIS pembayaran';
          wrap.appendChild(img);
        }
      } catch (error) {
        wrap.textContent = `Gagal membuat QR: ${error.message}`;
      }
    }
    area.hidden = false;
  }

  function renderChange() {
    const total = cartTotals().total;
    const received = Number($('#cashReceived').value || 0);
    const change = Math.max(0, received - total);
    $('#changeAmount').textContent = formatRupiah(change);
    $('#cashReceived').setCustomValidity(received > 0 && received < total ? 'Uang diterima kurang dari total' : '');
  }

  const PAYMENT_RECEIPT_TEXT = {
    cash: 'Pastikan uang tunai sudah diterima dari pelanggan sebelum transaksi diselesaikan.',
    qris: 'Pastikan QRIS sudah dibayar pelanggan sebelum transaksi diselesaikan.',
    transfer: 'Pastikan transfer sudah diterima sebelum transaksi diselesaikan.',
    card: 'Pastikan uang sudah diterima sebelum menyelesaikan transaksi.'
  };

  function completePayment() {
    const totals = cartTotals();
    if (!state.cart.length) return;
    const unavailableItems = state.cart.filter((item) => {
      const product = state.products.find((menuItem) => menuItem.id === item.productId);
      if (!product || !product.available) return true;
      const hasStockLimit = product.stock !== null && product.stock !== undefined && Number.isFinite(Number(product.stock));
      return hasStockLimit && item.qty > Number(product.stock);
    });
    if (unavailableItems.length) {
      const orphanNames = state.cart.filter((item) => cartItemMissing(item)).map((item) => cartItemName(item));
      showToast(
        orphanNames.length
          ? `${orphanNames.join(', ')} sudah tidak ada di daftar menu — hapus dari keranjang sebelum membayar.`
          : 'Ada menu yang tidak tersedia atau melebihi stok. Perbarui keranjang sebelum membayar.',
        6000
      );
      renderProducts();
      renderCart();
      return;
    }
    if (state.selectedPayment === 'cash') {
      const received = Number($('#cashReceived').value || 0);
      if (received < totals.total) {
        $('#cashReceived').focus();
        $('#cashReceived').setCustomValidity('Uang diterima kurang dari total');
        $('#cashReceived').reportValidity();
        return;
      }
    }
    $('#cashReceived').setCustomValidity('');
    askPaymentConfirmation(totals);
  }

  function askPaymentConfirmation(totals) {
    const payment = state.selectedPayment;
    const isCash = payment === 'cash';
    $('#paymentConfirmTitle').textContent = isCash ? 'Uang tunai sudah diterima?' : 'Pembayaran sudah diterima?';
    $('#confirmLead').textContent = PAYMENT_RECEIPT_TEXT[payment] || PAYMENT_RECEIPT_TEXT.cash;
    $('#confirmTotal').textContent = formatRupiah(totals.total);
    const changeRow = $('#confirmChangeRow');
    changeRow.hidden = !isCash;
    if (isCash) {
      const received = Number($('#cashReceived').value || 0);
      $('#confirmChange').textContent = formatRupiah(Math.max(0, received - totals.total));
    }
    const error = $('#confirmError');
    error.hidden = true;
    error.textContent = '';
    openModal('paymentConfirmModal');
  }

  function cancelPaymentConfirmation() {
    closeModal();
    openCheckout({ keepCashReceived: true, keepPayment: true });
    showToast('Transaksi belum disimpan. Periksa lagi pembayaran.');
  }

  function confirmPaymentReceived() {
    // Pagar ketuk-ganda: tombol konfirmasi sempat bisa terketuk dua kali -> transaksi kosong Rp 0
    if (!state.cart.length) {
      closeModal();
      renderCart();
      return;
    }
    const totals = cartTotals();
    const error = $('#confirmError');
    const received = state.selectedPayment === 'cash' ? Number($('#cashReceived').value || 0) : totals.total;
    if (state.selectedPayment === 'cash' && received < totals.total) {
      error.textContent = 'Uang diterima masih kurang dari total. Kembali ke pembayaran untuk memperbarui.';
      error.hidden = false;
      return;
    }
    const now = new Date();
    const order = {
      id: `MPJ-${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}-${String(Date.now()).slice(-5)}`,
      // UUID unik dari perangkat: kunci idempotency supaya kiriman ulang
      // (mis. respons pertama gagal sampai) tidak menggandakan transaksi.
      clientTxnId: (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') ? crypto.randomUUID() : undefined,
      createdAt: now.toISOString(),
      items: state.cart.map((item) => {
        const unit = cartItemPrice(item);
        return { productId: item.productId, name: cartItemName(item), price: unit, qty: item.qty, total: unit * item.qty, note: (item.note || '').trim() };
      }),
      orderType: state.orderType,
      tableNumber: state.orderType === 'dine-in' ? $('#tableNumber').value.trim() : '',
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      taxRate: state.settings.taxRate,
      taxIncluded: true,
      payment: state.selectedPayment,
      paidAmount: received,
      changeAmount: Math.max(0, received - totals.total),
      status: 'paid',
      cashier: state.user ? state.user.name : 'kasir',
      note: ($('#cartNoteInput')?.value || '').trim()
    };
    state.orders.push(order);
    deductPortionStock(order);
    state.currentOrder = order;
    // v12: pembayaran selesai = transaksi lunas. Langsung masuk riwayat
    // penjualan + struk, TIDAK lagi dimasukkan ke antrean "Bayar nanti".
    // Tab itu hanya diisi lewat tombol "⏸ Simpan nanti" (pesanan belum bayar).
    state.cart = [];
    $('#discountInput').value = '0';
    $('#tableNumber').value = '';
    const noteInput = $('#cartNoteInput');
    if (noteInput) noteInput.value = '';
    const stored = saveAll();
    if (!stored) showToast('Transaksi selesai tetapi gagal disimpan penuh — unduh backup di Pengaturan sekarang.', 8000);
    noteOrderSaved();
    renderDashboard();
    renderProducts();
    renderCart();
    renderMenuTable();
    renderReports();
    renderQueues();
    closeModal();
    showReceipt(order);
  }

  function deductPortionStock(order) {
    orderItems(order).forEach((orderItem) => {
      const product = state.products.find((item) => item.id === orderItem.productId);
      if (!product) return;
      const hasStockLimit = product.stock !== null && product.stock !== undefined && Number.isFinite(Number(product.stock));
      if (hasStockLimit) product.stock = Math.max(0, Number(product.stock) - orderItem.qty);
    });
  }

  const RECEIPT_PAYMENT_LABEL = { cash: 'Tunai', qris: 'QRIS', transfer: 'Transfer', card: 'Kartu' };

  // Jumlah item ala struk minimarket: "1,00" (dua angka di belakang koma).
  function receiptQty(value) {
    return Number(value || 0).toLocaleString('id-ID', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  // Layout struk mengikuti pola kasir minimarket: nama menu pada barisnya
  // sendiri, lalu baris "jumlah PCS x harga satuan =" dengan total item rata
  // kanan. Nilai transaksi (subtotal/total/pajak/diskon) tidak diubah.
  function renderReceiptPaper(order) {
    const typeLabelText = orderTypeLabel(order.orderType);
    const isCash = order.payment === 'cash';
    const paidAmount = Number.isFinite(Number(order.paidAmount)) ? Number(order.paidAmount) : order.total;
    const changeAmount = Number.isFinite(Number(order.changeAmount)) ? Number(order.changeAmount) : 0;
    const amount = (value) => formatNumber(value);
    const line = (label, value, className = '') => `<div class="receipt-line ${className}"><span>${escapeHtml(label)}</span><span>${escapeHtml(value)}</span></div>`;
    const itemRows = orderItems(order).map((item) => {
      const itemNote = (item.note || '').trim();
      const noteHtml = itemNote ? `<div class="receipt-item-note">📝 ${escapeHtml(itemNote)}</div>` : '';
      const detail = `${receiptQty(item.qty)} PCS  x  ${amount(item.price)} =`;
      return `<div class="receipt-item"><div class="receipt-item-name">${escapeHtml(item.name)}</div><div class="receipt-item-line"><span class="receipt-item-detail">${escapeHtml(detail)}</span><span class="receipt-item-amount">${amount(item.total)}</span></div>${noteHtml}</div>`;
    }).join('');
    const paymentLabelText = RECEIPT_PAYMENT_LABEL[order.payment] || paymentLabel(order.payment);
    const meta = [
      line('No. transaksi', order.id),
      line('Waktu', formatDateTime(order.createdAt)),
      order.cashier ? line('Kasir', order.cashier) : '',
      line('Pesanan', typeLabelText),
      order.tableNumber ? line('Meja', order.tableNumber) : ''
    ].join('');
    const money = [
      line('Subtotal', amount(order.subtotal)),
      order.discount ? line('Diskon', `-${amount(order.discount)}`) : '',
      `<div class="receipt-line receipt-total"><span>Total</span><span>${amount(order.total)}</span></div>`
    ].join('');
    // Info pembayaran hanya yang relevan: tunai menampilkan uang diterima +
    // kembalian (kembalian hanya bila ada), non-tunai menampilkan metodenya.
    const tender = [
      isCash
        ? line('Tunai', amount(paidAmount))
        : `<div class="receipt-line receipt-payment"><span>Metode bayar</span><span>${escapeHtml(paymentLabelText)}</span></div>`,
      isCash && changeAmount > 0 ? line('Kembali', amount(changeAmount)) : ''
    ].join('');
    const noteLine = order.note ? `<div class="receipt-note">📝 ${escapeHtml(order.note)}</div>` : '';

    return `${receiptHeaderHtml()}<div class="receipt-meta">${meta}</div><div class="receipt-rule" aria-hidden="true"></div><div class="receipt-items">${itemRows}</div><div class="receipt-rule" aria-hidden="true"></div><div class="receipt-money">${money}</div><div class="receipt-tender">${tender}</div>${noteLine}<div class="receipt-rule" aria-hidden="true"></div>${receiptFooterHtml()}`;
  }

  // Kepala struk dipakai struk penjualan maupun nota pesanan: nama usaha,
  // alamat (tiap baris dipisah), lalu nomor telepon/WA tersendiri.
  function receiptHeaderHtml() {
    const settings = state.settings;
    const addressLines = String(settings.businessAddress || '').split('\n').map((row) => row.trim()).filter(Boolean);
    const phoneText = String(settings.businessPhone || '').trim();
    return `<div class="receipt-center"><h3>${escapeHtml(settings.businessName)}</h3>${addressLines.map((row) => `<p>${escapeHtml(row)}</p>`).join('')}${phoneText ? `<p>Telp/WA: ${escapeHtml(phoneText)}</p>` : ''}</div>`;
  }

  function receiptFooterHtml(fallbackText) {
    const custom = (state.settings.receiptFooter || '').trim();
    const text = custom || fallbackText || 'Terima kasih sudah makan di tempat!\nSimpan struk ini sebagai bukti transaksi.';
    return `<div class="receipt-footer">${escapeHtml(text).replace(/\n/g, '<br />')}</div>`;
  }

  function showReceipt(order) {
    $('#receiptPaper').innerHTML = renderReceiptPaper(order);
    $('#receiptMetaLine').textContent = `${paymentLabel(order.payment)} · ${formatRupiah(order.total)}`;
    $('#receiptPaperSize').value = state.settings.receiptPaperSize || '58mm';
    applyReceiptPaperSize();
    openModal('receiptModal');
  }

  function applyReceiptPaperSize() {
    const size = state.settings.receiptPaperSize || '58mm';
    let style = document.getElementById('receiptPageStyle');
    if (!style) {
      style = document.createElement('style');
      style.id = 'receiptPageStyle';
      document.head.appendChild(style);
    }
    style.textContent = size === 'a4'
      ? '@media print { @page { size: A4 portrait; margin: 12mm; } }'
      : `@media print { @page { size: ${size} auto; margin: 3mm; } }`;
    document.body.classList.toggle('receipt-a4', size === 'a4');
  }

  /* ---------- Cetak khusus APK Android ----------
     WebView Android tidak mengimplementasikan window.print(), jadi tombol
     cetak tidak ada gunanya di sana. Plugin native "Print" (PrintPlugin.java
     di proyek Android) mencetak WebView UTAMA aplikasi lalu membuka dialog
     cetak Android bawaan: pilih printer fisik atau simpan PDF, dengan ukuran
     kertas sesuai pilihan struk (58 mm / 80 mm / A4). Supaya hasilnya sama
     dengan web, JS menyiapkan isi struk di #printArea dan menambah kelas
     body.is-printing-receipt SEBELUM memanggil plugin (media cetak hanya
     menampilkan .print-area). Tampilan dikembalikan lewat event
     "mpj-print-done" setelah pekerjaan cetak selesai/dibatalkan.
     Website biasa tidak punya plugin ini sehingga jalur window.print() lama
     tetap dipakai tanpa perubahan. */
  function isNativeApp() {
    const cap = window.Capacitor;
    return Boolean(cap && typeof cap.isNativePlatform === 'function' && cap.isNativePlatform());
  }

  /*
     Ambil plugin native Capacitor dengan nama yang sama di MainActivity.
     Di WebView aplikasi, window.Capacitor adalah bridge NATIVE: plugin yang
     didaftarkan di MainActivity menempel otomatis di Capacitor.Plugins.<nama>
     (inilah jalur yang dipakai dan terbukti jalan lewat plugin Print sejak v9).
     registerPlugin adalah API bundle web @capacitor/core yang TIDAK dimuat di
     WebView; tetap dicoba sebagai cadangan bila bundle itu terpasang.
  */
  function nativePlugin(name) {
    const cap = window.Capacitor;
    if (!cap || !isNativeApp()) return null;
    const cacheKey = '__mpjNativePlugin_' + name;
    if (cap[cacheKey] === undefined) {
      let plugin = null;
      if (cap.Plugins && cap.Plugins[name]) plugin = cap.Plugins[name];
      if (!plugin && typeof cap.registerPlugin === 'function') {
        try { plugin = cap.registerPlugin(name); } catch (error) { plugin = null; }
      }
      cap[cacheKey] = plugin || null;
    }
    return cap[cacheKey];
  }

  function nativePrinter() {
    return nativePlugin('Print');
  }

  function printViaAndroid(name, okMessage) {
    if (!isNativeApp()) return 'web'; // website biasa -> jalur window.print() lama
    const printer = nativePrinter();
    if (!printer || typeof printer.print !== 'function') {
      // Jangan diam: tanpa plugin cetak, window.print() di Android = tidak
      // terjadi apa-apa. Kasir perlu tahu ini bug integrasi, bukan salah tekan.
      showToast('Komponen cetak aplikasi belum siap di perangkat ini (plugin Print tidak ditemukan). Beri tahu teknisi.', 6000);
      return 'error';
    }
    const size = state.settings.receiptPaperSize || '58mm';
    // Tidak mengirim content: plugin mencetak WebView utama yang isinya sudah
    // disiapkan di #printArea (lihat printReceipt / printOnlineTicket).
    printer.print({ name, paperSize: size })
      .then(() => showToast(okMessage))
      .catch((error) => showToast(`Dialog cetak gagal dibuka (${error && error.message ? error.message : 'tanpa keterangan'}). Coba lagi.`, 6000));
    return 'native';
  }

  /* ---------- Printer Bluetooth 58 mm (iware X58BT II / MP58) ----------
     Karena printer termal ini tidak bisa dipakai lewat dialog cetak Android
     (mereka butuh sambungan Bluetooth SPP + perintah ESC/POS), aplikasi
     memakai plugin native "BluetoothThermal" yang mengirim teks struk
     langsung ke printer, bukan dialog cetak. Diatur di Pengaturan →
     Printer Bluetooth 58 mm. Kalau belum diatur, cetak tetap memakai dialog
     cetak Android biasa (plugin "Print"). */
  function nativeBluetoothPrinter() {
    return nativePlugin('BluetoothThermal');
  }

  function btPrinterConfigured() {
    return Boolean(state.settings.printerModel && state.settings.printerAddress);
  }

  // Ubah isi struk (DOM #receiptPaper / #printArea) menjadi daftar baris
  // ESC/POS: [teks, perataan 0=kiri/1=tengah, tebal 0/1, ukuran 0/1/2/3].
  // Baris berisi tanda \t dipecah menjadi dua kolom (kiri disandarkan, kanan
  // diratakan ke tepi) oleh plugin native. `paperWidth` = lebar karakter kertas
  // (32 untuk 58 mm, 48 untuk 80 mm) dipakai untuk garis pemisah.
  function escposPaperToData(paper, paperWidth) {
    if (!paper || !paper.querySelector) return null;
    const width = paperWidth === 48 ? 48 : 32;
    const segs = [];
    const sanitizePiece = (value) => String(value ?? '')
      .replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"')
      .replace(/[\u2013\u2014]/g, '-').replace(/\u2022/g, '-').replace(/\u00A0/g, ' ')
      .replace(/[^\x20-\x7E\u00A0-\u00FF]/g, '')
      .replace(/\s+/g, ' ').trim();
    // Tab (pemisah kolom kiri/kanan) harus tetap ada supaya plugin bisa
    // menyandarkan harga ke tepi kanan, jadi tab disanitasi per bagian.
    const sanitize = (value) => String(value ?? '').split('\t').map(sanitizePiece).join('\t');
    const push = (text, align = 0, bold = 0, size = 0) => segs.push([sanitize(text), align, bold, size]);
    const pushRow = (row) => {
      const left = row.children[0] ? row.children[0].textContent : '';
      const right = row.children[1] ? row.children[1].textContent : '';
      const total = row.classList.contains('receipt-total');
      push(`${left}\t${right}`, 0, total || row.classList.contains('receipt-payment') ? 1 : 0, total ? 2 : 0);
    };
    const walkChild = (child) => {
      if (!child || child.nodeType !== 1) return;
      if (child.classList.contains('receipt-center')) {
        const h3 = child.querySelector(':scope > h3');
        if (h3) push(h3.textContent, 1, 1, 2);
        child.querySelectorAll(':scope > p').forEach((pEl) => push(pEl.textContent, 1));
        return;
      }
      if (child.classList.contains('receipt-rule')) { push('-'.repeat(width), 0); return; }
      if (child.classList.contains('receipt-meta') || child.classList.contains('receipt-money') || child.classList.contains('receipt-tender')) {
        // Beri satu baris kosong sebelum bagian pembayaran (seperti struk
        // minimarket: total lalu jeda, baru tunai/kembali).
        if (child.classList.contains('receipt-tender')) push(' ', 0);
        child.querySelectorAll(':scope > .receipt-line').forEach(pushRow);
        return;
      }
      if (child.classList.contains('receipt-items')) {
        [...child.children].forEach((el) => {
          if (el.classList.contains('receipt-item')) {
            const nameEl = el.querySelector(':scope > .receipt-item-name');
            if (nameEl) push(nameEl.textContent, 0);
            const detailEl = el.querySelector(':scope > .receipt-item-line');
            if (detailEl) pushRow(detailEl);
            const noteEl = el.querySelector(':scope > .receipt-item-note');
            if (noteEl) push(noteEl.textContent, 0);
          } else if (el.classList.contains('receipt-line')) {
            pushRow(el);
          } else if (el.classList.contains('receipt-item-note')) {
            push(el.textContent, 0);
          }
        });
        return;
      }
      if (child.classList.contains('receipt-note')) { push(child.textContent, 0); return; }
      if (child.classList.contains('receipt-footer')) {
        const plain = child.innerHTML.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]*>/g, '')
          .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#039;/g, "'").replace(/&quot;/g, '"');
        plain.split('\n').forEach((line) => push(line.trim() ? line.trim() : ' ', 1));
      }
    };
    if (paper.children) {
      for (const child of paper.children) walkChild(child);
    } else {
      walkChild(paper);
    }
    return JSON.stringify(segs);
  }

  // Kirim struk ke printer Bluetooth bila sudah diatur. Mengembalikan true
  // kalau cetak dikirim lewat Bluetooth (JS tidak perlu dialog cetak), false
  // untuk lanjut ke jalur cetak lama.
  function tryBluetoothPrint(name, paper) {
    if (!isNativeApp()) return false;
    const plugin = nativeBluetoothPrinter();
    if (!plugin || typeof plugin.print !== 'function') return false;
    if (!btPrinterConfigured()) return false;
    const width = state.settings.receiptPaperSize === '80mm' ? 48 : 32;
    const data = escposPaperToData(paper, width);
    if (!data) return false;
    plugin.print({ address: state.settings.printerAddress, data, width })
      .then(() => showToast(`${name} terkirim ke printer Bluetooth.`))
      .catch((error) => showToast(`Cetak Bluetooth gagal (${error && error.message ? error.message : 'periksa koneksi printer'}). Coba lagi atau pakai dialog cetak biasa.`, 6000));
    return true;
  }

  function refreshBluetoothDevices() {
    if (!isNativeApp()) {
      showToast('Daftar printer Bluetooth hanya tersedia di aplikasi Android.', 5000);
      return;
    }
    const plugin = nativeBluetoothPrinter();
    if (!plugin || typeof plugin.listDevices !== 'function') {
      showToast('Komponen Bluetooth belum siap di perangkat ini (plugin BluetoothThermal tidak ditemukan). Beri tahu teknisi.', 6000);
      return;
    }
    const btn = document.querySelector('[data-action="refresh-bt-devices"]');
    if (btn) { btn.disabled = true; btn.textContent = 'Memuat…'; }
    plugin.listDevices()
      .then((result) => {
        const select = $('#printerDevice');
        if (!select) return;
        const devices = (result && result.devices) || [];
        const previous = state.settings.printerAddress || '';
        select.innerHTML = '<option value="">— pilih perangkat yang sudah dipasangkan —</option>';
        devices.forEach((device) => {
          const option = document.createElement('option');
          option.value = device.address;
          option.textContent = device.name || device.address;
          select.appendChild(option);
        });
        if (previous) select.value = previous;
        showToast(devices.length ? `${devices.length} perangkat Bluetooth ditemukan. Pilih printer di daftar.` : 'Tidak ada perangkat Bluetooth yang dipasangkan. Tekan "⚙ Buka Bluetooth HP", pasangkan printer (kode 0000/1234), lalu kembali dan tekan "↻ Muat ulang daftar".', 8000);
      })
      .catch((error) => showToast(`Gagal memuat daftar Bluetooth (${error && error.message ? error.message : 'izin Bluetooth belum diberikan. Buka Pengaturan → Izin aplikasi dan izinkan Bluetooth.'}).`, 6000))
      .finally(() => {
        if (btn) { btn.disabled = false; btn.textContent = '↻ Muat ulang daftar'; }
      });
  }

  // Buka Pengaturan Bluetooth HP dari dalam aplikasi: printer termal harus
  // dipasangkan lewat menu sistem Android dulu sebelum bisa dipilih di sini.
  function openBluetoothSettings() {
    const plugin = nativeBluetoothPrinter();
    if (!plugin || typeof plugin.openBluetoothSettings !== 'function') {
      showToast('Buka Pengaturan → Bluetooth di HP, pasangkan printer (kode 0000/1234), lalu kembali ke sini.', 6000);
      return;
    }
    plugin.openBluetoothSettings()
      .then(() => showToast('Pengaturan Bluetooth HP dibuka. Pasangkan printer, lalu kembali dan tekan "↻ Muat ulang daftar".', 6000))
      .catch((error) => showToast(`Tidak bisa membuka pengaturan Bluetooth (${error && error.message ? error.message : 'buka manual dari Pengaturan HP'}).`, 6000));
  }

  function testBluetoothPrint() {
    if (!isNativeApp()) {
      showToast('Test cetak hanya tersedia di aplikasi Android dengan printer Bluetooth.', 5000);
      return;
    }
    const plugin = nativeBluetoothPrinter();
    if (!plugin || typeof plugin.print !== 'function') {
      showToast('Komponen Bluetooth belum siap di perangkat ini (plugin BluetoothThermal tidak ditemukan). Beri tahu teknisi.', 6000);
      return;
    }
    if (!btPrinterConfigured()) {
      showToast('Pilih model dan perangkat printer Bluetooth dulu di atas.', 5000);
      return;
    }
    const width = state.settings.receiptPaperSize === '80mm' ? 48 : 32;
    const lines = [
      [state.settings.businessName || 'Mie Pangsit Jakarta', 1, 1, 0],
      ['', 0, 0, 0],
      ['TEST CETAK PRINTER', 1, 1, 0],
      ['', 0, 0, 0],
      ['Jika tulisan ini rapi', 0, 0, 0],
      ['dan kertas terpotong,', 0, 0, 0],
      ['printer siap dipakai.', 0, 0, 0],
      ['', 0, 0, 0],
      [new Date().toLocaleString('id-ID'), 1, 0, 0],
      ['', 0, 0, 0],
      ['— SELESAI —', 1, 1, 0]
    ];
    plugin.print({ address: state.settings.printerAddress, data: JSON.stringify(lines), width })
      .then(() => showToast('Test cetak terkirim ke printer Bluetooth.'))
      .catch((error) => showToast(`Test cetak gagal (${error && error.message ? error.message : 'periksa koneksi printer'}).`, 6000));
  }

  // Cetak native sedang berjalan. Dua titik sentuh "Cetak" yang berurutan cepat
  // tidak boleh saling menghapus isi #printArea — cetak kedua ditolak dengan
  // pesan singkat sampai pekerjaan pertama selesai (event mpj-print-done).
  let nativePrintBusy = false;

  function deferRestoreAfterPrint(restore) {
    // WebView utama dicetak, jadi tidak bisa langsung mengembalikan tampilan:
    // background dia tetap normal (kelas .is-printing-receipt hanya berpengaruh
    // di media cetak), tapi isi printArea dan kelas itu harus dipertahankan
    // sampai event "mpj-print-done" datang dari plugin native.
    nativePrintBusy = true;
    let timer = 0;
    const done = () => {
      window.clearTimeout(timer);
      window.removeEventListener('mpj-print-done', done);
      nativePrintBusy = false;
      restore();
    };
    // Pengaman: kalau perangkat aneh dan event tak pernah datang, kembalikan
    // layar setelah beberapa menit agar aplikasi tidak macet.
    timer = window.setTimeout(done, 3 * 60 * 1000);
    window.addEventListener('mpj-print-done', done);
  }

  function printReceipt() {
    const paper = $('#receiptPaper');
    if (!paper) return;
    if (nativePrintBusy) {
      showToast('Cetak sebelumnya masih berjalan. Tunggu sampai dialog cetak selesai.', 4000);
      return;
    }
    // Printer Bluetooth sudah diatur -> kirim langsung, tanpa dialog cetak.
    if (tryBluetoothPrint('Struk Mie Pangsit Jakarta', paper)) return;
    const printArea = $('#printArea');
    const previousOverflow = document.body.style.overflow;
    const previousHeight = document.body.style.height;
    // Pindahkan struk ke area cetak terpisah. Kelas .is-printing-receipt hanya
    // berpengaruh di media cetak, jadi di layar tidak ada perubahan kasat mata.
    printArea.innerHTML = paper.innerHTML;
    document.body.classList.add('is-printing-receipt');
    const restore = () => {
      printArea.innerHTML = '';
      document.body.classList.remove('is-printing-receipt');
      document.body.style.overflow = previousOverflow;
      document.body.style.height = previousHeight;
      window.removeEventListener('afterprint', restore);
    };
    const via = printViaAndroid('Struk Mie Pangsit Jakarta', 'Dialog cetak terbuka. Pilih printer dan ukuran kertas yang sesuai.');
    if (via === 'web') {
      document.body.style.overflow = 'visible';
      document.body.style.height = 'auto';
      window.addEventListener('afterprint', restore);
      window.print();
      restore();
      showToast('Dialog cetak terbuka. Pilih printer dan ukuran kertas yang sesuai.');
    } else if (via === 'native') {
      // Print Preview tidak ikut merender header/footer modal; isi halaman di
      // media cetak hanya .print-area. Tampilan dikembalikan oleh plugin lewat
      // event "mpj-print-done", atau pengaman waktu di deferRestoreAfterPrint.
      deferRestoreAfterPrint(restore);
    } else {
      restore(); // plugin tidak ada -> kembalikan layar, jangan biarkan berubah
    }
  }

  function reprintOrder(orderId) {
    // Utamakan transaksi di riwayat; kalau tidak ada (mis. riwayat sudah dibersihkan),
    // pakai entri "Pesanan dibuat" — datanya cukup untuk memunculkan struk lagi.
    const order = state.orders.find((item) => item.id === orderId)
      || state.pendingOrders.find((item) => item.id === orderId);
    if (!order) {
      showToast('Transaksi tidak ditemukan.');
      return;
    }
    showReceipt(order);
    showToast('Struk dimuat. Tekan "Cetak struk" untuk mencetak ulang.');
  }

  /* v12 — hapus satu transaksi dari Laporan (khusus akun Pemilik).
     Dipakai kalau ada salah catat/miss pembayaran. Transaksi dibuang dari
     riwayat lokal dan diantrekan sebagai tombstone ke server (server menandai
     deleted = true + mencatat audit), jadi perangkat lain ikut menghapusnya.
     Stok TIDAK dikembalikan otomatis — catat penyesuaian manual bila perlu. */
  function deleteReportOrder(orderId) {
    if (!isOwnerUser()) {
      showToast('Hapus transaksi hanya bisa dipakai oleh akun pemilik.');
      return;
    }
    const id = String(orderId || '');
    const order = state.orders.find((item) => item.id === orderId);
    if (!order) { showToast('Transaksi tidak ditemukan.'); return; }
    const items = orderItems(order).map((item) => `${item.qty}× ${item.name}`).join(', ');
    const yakin = window.confirm(
      'Hapus transaksi ' + orderId + ' dari laporan?\n\n' +
      `${formatDateTime(order.createdAt)} · ${formatRupiah(order.total)} (${paymentLabel(order.payment)})\n` +
      `${items}\n\n` +
      'Transaksi ini hilang dari riwayat & laporan di SEMUA perangkat dan tidak bisa dikembalikan. ' +
      'Gunakan hanya kalau catatannya salah (mis. miss pembayaran).'
    );
    if (!yakin) return;
    state.orders = state.orders.filter((item) => item.id !== orderId);
    // Entri lama di antrean "Bayar nanti" yang memakai id sama ikut dibuang
    // supaya tidak meninggalkan pesanan yatim.
    const beforePending = state.pendingOrders.length;
    state.pendingOrders = state.pendingOrders.filter((item) => item.id !== orderId);
    const saved = save(STORAGE_KEYS.orders, state.orders);
    if (beforePending !== state.pendingOrders.length) save(STORAGE_KEYS.pending, state.pendingOrders);
    renderDashboard();
    renderReports();
    renderQueues();
    if (saved) showToast(`Transaksi ${orderId} dihapus dari laporan.`);
    else showToast('Transaksi dihapus dari layar, tetapi penyimpanan perangkat penuh — perubahan BELUM tersimpan.', 7000);
  }

  /* v12: cetak pesanan online = STRUK PELANGGAN (dulu nota untuk dapur).
     Tersedia di semua tahap (Baru / Dibuat / Siap diambil) supaya kasir tidak
     perlu mencetak dua kali dan kertas tidak terbuang saat pesanan dibuat. */
  function renderOnlineTicket(order) {
    const platform = ONLINE_PLATFORMS[order.source] || ONLINE_PLATFORMS.other;
    const amount = (value) => formatNumber(value);
    const line = (label, value, className = '') => `<div class="receipt-line ${className}"><span>${escapeHtml(label)}</span><span>${escapeHtml(value)}</span></div>`;
    const items = orderItems(order);
    const itemRows = items.map((item) => {
      const itemNote = (item.note || '').trim();
      const noteHtml = itemNote ? `<div class="receipt-item-note">📝 ${escapeHtml(itemNote)}</div>` : '';
      const detail = `${receiptQty(item.qty)} PCS  x  ${amount(item.price)} =`;
      return `<div class="receipt-item"><div class="receipt-item-name">${escapeHtml(item.name)}</div><div class="receipt-item-line"><span class="receipt-item-detail">${escapeHtml(detail)}</span><span class="receipt-item-amount">${amount(item.total)}</span></div>${noteHtml}</div>`;
    }).join('');
    const subtotal = Number.isFinite(Number(order.subtotal))
      ? Number(order.subtotal)
      : items.reduce((sum, item) => sum + Number(item.total || 0), 0);
    const total = Number.isFinite(Number(order.total)) ? Number(order.total) : subtotal;
    const meta = [
      line('No. pesanan', order.code || order.id),
      line('Platform', platform.label),
      order.customer ? line('Pelanggan', order.customer) : '',
      line('Waktu', formatDateTime(order.createdAt)),
      order.status === 'siap' && order.pickupCode ? line('Kode ambil', order.pickupCode) : ''
    ].join('');
    const money = [
      line('Subtotal', amount(subtotal)),
      `<div class="receipt-line receipt-total"><span>Total</span><span>${amount(total)}</span></div>`
    ].join('');
    const noteLine = order.note ? `<div class="receipt-note">📝 ${escapeHtml(order.note)}</div>` : '';
    return `${receiptHeaderHtml()}<div class="receipt-meta">${meta}</div><div class="receipt-rule" aria-hidden="true"></div><div class="receipt-items">${itemRows}</div><div class="receipt-rule" aria-hidden="true"></div><div class="receipt-money">${money}</div>${noteLine}<div class="receipt-rule" aria-hidden="true"></div>${receiptFooterHtml('Terima kasih sudah memesan!\nSimpan struk ini sebagai bukti transaksi.')}`;
  }

  function printOnlineTicket(order) {
    const printArea = $('#printArea');
    if (!printArea) return;
    if (nativePrintBusy) {
      showToast('Cetak sebelumnya masih berjalan. Tunggu sampai dialog cetak selesai.', 4000);
      return;
    }
    printArea.innerHTML = renderOnlineTicket(order);
    // Printer Bluetooth sudah diatur -> kirim langsung, tanpa dialog cetak.
    if (tryBluetoothPrint('Struk Mie Pangsit Jakarta', printArea)) {
      printArea.innerHTML = '';
      return;
    }
    const previousOverflow = document.body.style.overflow;
    const previousHeight = document.body.style.height;
    printArea.innerHTML = renderOnlineTicket(order);
    document.body.classList.add('is-printing-receipt');
    const restore = () => {
      printArea.innerHTML = '';
      document.body.classList.remove('is-printing-receipt');
      document.body.style.overflow = previousOverflow;
      document.body.style.height = previousHeight;
      window.removeEventListener('afterprint', restore);
    };
    const via = printViaAndroid('Struk Mie Pangsit Jakarta', 'Struk pelanggan dikirim ke printer.');
    if (via === 'web') {
      document.body.style.overflow = 'visible';
      document.body.style.height = 'auto';
      window.addEventListener('afterprint', restore);
      window.print();
      restore();
      showToast('Struk pelanggan dikirim ke printer.');
    } else if (via === 'native') {
      deferRestoreAfterPrint(restore);
    } else {
      restore();
    }
  }

  function printOnlineTicketById(orderId) {
    const order = state.onlineOrders.find((online) => online.id === orderId);
    if (!order) {
      showToast('Pesanan tidak ditemukan.');
      return;
    }
    printOnlineTicket(normalizeOnlineOrder(order));
  }

  function newOrder() {
    closeModal();
    switchCartTab('cart');
    navigate('cashier');
    toggleOrdersSlider(false); // transaksi baru: menu langsung full satu layar
    const noteInput = $('#cartNoteInput');
    if (noteInput) noteInput.value = '';
    showToast('Siap membuat transaksi baru.');
  }

  function switchCartTab(tab) {
    state.cartTab = normalizeCartTab(tab);
    save(STORAGE_KEYS.cartTab, state.cartTab); // tab aktif diingat, jadi setelah refresh kasir kembali ke "Dibuat" bukan ke Keranjang
    $$('#cartTabs button').forEach((button) => {
      const active = button.dataset.cartTab === tab;
      button.classList.toggle('is-active', active);
      button.setAttribute('aria-selected', String(active));
    });
    const panels = { cart: $('#cartTabPanel'), pending: $('#pendingTabPanel'), online: $('#onlineTabPanel') };
    Object.keys(panels).forEach((key) => { const panelEl = panels[key]; if (panelEl) panelEl.hidden = key !== tab; });
    renderQueues();
  }

  function updateQueueBadges() {
    const pendingBadge = $('#pendingCountBadge');
    if (pendingBadge) { pendingBadge.textContent = state.pendingOrders.length; pendingBadge.hidden = !state.pendingOrders.length; }
    const onlineBadge = $('#onlineCountBadge');
    if (onlineBadge) { onlineBadge.textContent = state.onlineOrders.length; onlineBadge.hidden = !state.onlineOrders.length; }
  }

  function renderQueues() {
    healPendingList();
    ensurePickupCodes();
    updateQueueBadges();
    // Pagar terakhir: satu data aneh tidak boleh membuat seluruh panel kosong
    try {
      renderPendingList();
      renderOnlineList();
    } catch (error) {
      console.error('Gagal menampilkan antrean', error);
      const pendingEl = $('#pendingList');
      if (pendingEl && state.pendingOrders.length) pendingEl.innerHTML = `<div class="empty-queue"><span>⚠</span><strong>${formatNumber(state.pendingOrders.length)} pesanan tersimpan</strong><small>Daftar tidak bisa dirender. Buka Pengaturan → Cadangkan data, lalu muat ulang aplikasi.</small></div>`;
      showToast('Ada masalah menampilkan antrean. Data tetap tersimpan.', 6000);
    }
  }

  /* Data antrean bisa saja rusak (impor manual, versi lama, storage penuh).
     Sebelum dirender, dibetulkan dulu lalu disimpan ulang — supaya tidak
     perlu kasir membuka tiap pesanan satu per satu. */
  function healPendingList() {
    try {
      const list = normalizePendingList(state.pendingOrders);
      if (pendingSignature(list) === pendingSignature(state.pendingOrders)) return;
      state.pendingOrders = list;
      savePending();
    } catch (error) {
      console.warn('Daftar pesanan tidak bisa dirapikan', error);
    }
  }

  function pendingSignature(list) {
    if (!Array.isArray(list)) return '';
    return list.map((order) => {
      if (!order || typeof order !== 'object') return 'x';
      const items = Array.isArray(order.items) ? order.items : [];
      return `${order.id || ''}#${order.status || ''}#${items.length}`;
    }).join('|');
  }

  function normalizeCartTab(value) {
    return ['cart', 'pending', 'online'].includes(value) ? value : 'cart';
  }

  function renderPendingList() {
    const list = $('#pendingList');
    const hint = $('#pendingListHint');
    if (!list) return;
    if (!state.pendingOrders.length) {
      list.innerHTML = '<div class="empty-queue"><span>📋</span><strong>Belum ada pesanan disimpan</strong><small>Tekan "⏸ Simpan nanti" di keranjang untuk menahan pesanan yang dibayar belakangan. Pesanan yang dibayar langsung tidak masuk daftar ini.</small></div>';
      if (hint) hint.textContent = '−';
      return;
    }
    if (hint) hint.textContent = `${state.pendingOrders.length} antrean${pendingRecoveryNote ? ` · ${pendingRecoveryNote}` : ''}`;
    list.innerHTML = state.pendingOrders.slice().reverse().map((order) => {
      const unpaid = order.status !== 'preparing';
      const typeText = orderTypeLabel(order.orderType);
      const itemsText = orderItems(order).map((item) => `${item.qty}× ${item.name}`).join(', ');
      const cancelBtn = unpaid
        ? `<button class="queue-cancel" type="button" data-action="cancel-pending" data-order-id="${escapeAttr(order.id)}" title="Batalkan pesanan ${escapeAttr(order.id)}" aria-label="Batalkan pesanan ${escapeAttr(order.id)}">✕</button>`
        : '';
      return `<div class="queue-item" data-pending-id="${escapeAttr(order.id)}">
        <span class="queue-item-top"><strong>${escapeHtml(order.id)}</strong><span class="queue-item-head"><span class="status-pill ${unpaid ? 'pending' : 'available'}">${unpaid ? 'Belum bayar' : 'Dibuat'}</span>${cancelBtn}</span></span>
        <span class="queue-item-sub">${escapeHtml(typeText)}${order.tableNumber ? ` · Meja ${escapeHtml(order.tableNumber)}` : ''} · ${formatTime(order.createdAt)}</span>
        <span class="queue-item-items" title="${escapeAttr(itemsText)}">${escapeHtml(itemsText)}</span>
        <span class="queue-item-foot"><strong>${formatRupiah(order.total)}</strong><i>›</i></span>
      </div>`;
    }).join('');
  }

  /* ---------- Panel geser "Pesanan Pelanggan" (khusus layar kasir) ----------
     Menu kasir satu layar penuh; tiket pesanan & antrean dibuka lewat kotak
     di tepi kanan atau tab topbar. Isi panel = 3 tab (Keranjang / Dibuat /
     Online) yang disinkronkan lewat switchCartTab + data-cart-tab. */
  function toggleOrdersSlider(force) {
    const slider = $('#ordersSlider');
    if (!slider) return;
    const open = force === undefined ? !slider.classList.contains('is-open') : Boolean(force);
    slider.classList.toggle('is-open', open);
    slider.setAttribute('aria-hidden', String(!open));
    const handle = $('#ordersSliderHandle');
    if (handle) handle.setAttribute('aria-expanded', String(open));
    if (open) renderQueues(); // segarkan antrean setiap panel dibuka
  }

  function renderOnlineStatusChips() {
    const bar = $('#onlineStatusBar');
    if (!bar) return;
    const counts = {};
    state.onlineOrders.forEach((order) => { counts[order.status] = (counts[order.status] || 0) + 1; });
    const chips = ['baru', 'dibuat', 'siap'].map((status) => {
      const count = counts[status] || 0;
      const active = state.onlineStatusFilter === status ? ' is-active' : '';
      return `<button type="button" class="queue-chip${active}" data-action="online-status-filter" data-status="${escapeAttr(status)}" aria-pressed="${active ? 'true' : 'false'}"><span class="queue-chip-label">${escapeHtml(ONLINE_STATUS[status] || status)}</span><b>${count}</b></button>`;
    }).join('');
    bar.innerHTML = chips;
  }

  function setOnlineStatusFilter(status) {
    if (!['baru', 'dibuat', 'siap'].includes(status)) return;
    state.onlineStatusFilter = status;
    renderQueues();
  }

  // Filter platform mitra (GoFood/ShopeeFood/GrabFood) untuk tab Online.
  // Bermanfaat saat integrasi API Grab/Shopee/GoFood aktif nanti.
  function renderOnlinePlatformChips() {
    const bar = $('#onlinePlatformBar');
    if (!bar) return;
    const active = state.onlinePlatformFilter || 'all';
    const keys = Object.keys(ONLINE_PLATFORMS).filter((key) => key !== 'other' || state.onlineOrders.some((order) => order.source === 'other'));
    const chips = [`<button type="button" class="queue-chip${active === 'all' ? ' is-active' : ''}" data-action="online-platform-filter" data-platform="all" aria-pressed="${active === 'all' ? 'true' : 'false'}">Semua</button>`];
    keys.forEach((key) => {
      const count = state.onlineOrders.filter((order) => order.source === key).length;
      chips.push(`<button type="button" class="queue-chip${active === key ? ' is-active' : ''}" data-action="online-platform-filter" data-platform="${escapeAttr(key)}" aria-pressed="${active === key ? 'true' : 'false'}">${escapeHtml(ONLINE_PLATFORMS[key].label)}${count ? ` <b>${count}</b>` : ''}</button>`);
    });
    bar.innerHTML = chips.join('');
  }

  function setOnlinePlatformFilter(platform) {
    state.onlinePlatformFilter = platform || 'all';
    renderQueues();
  }

  function renderOnlineList() {
    const list = $('#onlineList');
    if (!list) return;
    const hint = $('#onlineListHint');
    if (hint) hint.textContent = state.onlineOrders.length ? `${formatNumber(state.onlineOrders.length)} pesanan` : '−';
    renderOnlineStatusChips();
    renderOnlinePlatformChips();
    const status = state.onlineStatusFilter || 'baru';
    const platformFilter = state.onlinePlatformFilter || 'all';
    const filtered = state.onlineOrders.filter((order) => order.status === status && (platformFilter === 'all' || order.source === platformFilter));
    const statusLabel = ONLINE_STATUS[status] || status;
    if (!filtered.length) {
      list.innerHTML = `<div class="empty-queue"><span>🛵</span><strong>Tidak ada pesanan ${escapeHtml(statusLabel)}</strong><small>Pesanan dari GoFood / ShopeeFood / GrabFood yang masuk akan muncul di sini secara otomatis.</small></div>`;
      return;
    }
    list.innerHTML = filtered.slice().reverse().map((rawOrder) => {
      const order = normalizeOnlineOrder(rawOrder);
      const platform = ONLINE_PLATFORMS[order.source] || ONLINE_PLATFORMS.other;
      const itemsText = orderItems(order).map((item) => `${item.qty}× ${item.name}`).join(', ');
      const pickup = order.status === 'siap' && order.pickupCode ? ` · Kode ambil <b class="pickup-inline">${escapeHtml(order.pickupCode)}</b>` : '';
      // v12: tombol batalkan di UJUNG KIRI tiap kartu (semua tahap, termasuk
      // "Siap diambil") — supaya salah tekan status bisa dibatalkan dengan cepat.
      const cancelBtn = `<button class="queue-cancel" type="button" data-action="cancel-online" data-order-id="${escapeAttr(order.id)}" title="Batalkan pesanan ${escapeAttr(order.code || order.id)}" aria-label="Batalkan pesanan ${escapeAttr(order.code || order.id)}">✕</button>`;
      return `<div class="queue-item" data-online-id="${escapeAttr(order.id)}">
        <span class="queue-item-top"><span class="queue-item-head">${cancelBtn}<strong class="platform-label ${escapeAttr(order.source)}">${escapeHtml(platform.label)}</strong></span><span class="status-pill ${ONLINE_STATUS_CLASS[order.status] || 'pending'}">${ONLINE_STATUS[order.status] || order.status}</span></span>
        <span class="queue-item-sub">${escapeHtml(order.code)}${order.customer ? ` · ${escapeHtml(order.customer)}` : ''} · ${formatTime(order.createdAt)}${pickup}</span>
        <span class="queue-item-items" title="${escapeAttr(itemsText)}">${escapeHtml(itemsText)}</span>
        <span class="queue-item-foot"><strong>${formatRupiah(order.total)}</strong><i>›</i></span>
      </div>`;
    }).join('');
  }

  function resolveOnlineOrderItems(items) {
    const resolved = [];
    (items || []).forEach((entry) => {
      const product = state.products.find((menuItem) => menuItem.id === entry.productId);
      if (!product) return;
      const qty = Math.max(1, Math.floor(Number(entry.qty) || 1));
      // Harga online: utamakan harga dari payload platform (API GoFood/Shopee/Grab) —
      // jangan ditimpa harga lokal. Fallback ke Harga jual hanya bila payload tidak
      // membawa harga (mis. simulasi dummy atau pesanan tanpa harga).
      const payloadPrice = Number(entry.price);
      const price = Number.isFinite(payloadPrice) ? payloadPrice : (Number(product.price) || 0);
      resolved.push({ productId: product.id, name: product.name, price, qty, total: price * qty });
    });
    return resolved;
  }

  // Belum ada API mitra: buat kode unik dummy. GoFood/Grab memakai 4 digit
  // seperti aslinya; ShopeeFood memakai nomor pesanan dari aplikasi.
  function makePickupCode(order) {
    if (order.source === 'gofood' || order.source === 'grab') {
      return String(Math.floor(1000 + Math.random() * 9000));
    }
    return order.code || '0000';
  }

  function ensurePickupCodes() {
    let changed = false;
    state.onlineOrders.forEach((order) => {
      if (order.status === 'siap' && !order.pickupCode) {
        order.pickupCode = makePickupCode(order);
        changed = true;
      }
    });
    if (changed) saveOnline();
  }

  function normalizeOnlineOrder(order) {
    const items = resolveOnlineOrderItems(order.items);
    const subtotal = items.reduce((sum, item) => sum + item.total, 0);
    const discount = Number(order.discount) || 0;
    return {
      ...order,
      id: order.id || `ONL-${order.code || Date.now()}`,
      items,
      subtotal,
      discount,
      total: Number.isFinite(Number(order.total)) ? Number(order.total) : Math.max(0, subtotal - discount)
    };
  }

  function holdOrder() {
    if (!state.cart.length) return;
    const items = state.cart.map((item) => {
      const product = state.products.find((menuItem) => menuItem.id === item.productId);
      if (!product) return null;
      const unit = unitPrice(product);
      return { productId: product.id, name: product.name, price: unit, qty: item.qty, total: unit * item.qty, note: (item.note || '').trim() };
    }).filter(Boolean);
    if (!items.length) {
      showToast('Semua menu di keranjang sudah tidak ada. Kosongkan keranjang dulu.', 6000);
      return;
    }
    const totals = cartTotals();
    const now = new Date();
    const order = {
      id: `HOLD-${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}-${String(Date.now()).slice(-5)}`,
      createdAt: now.toISOString(),
      orderType: state.orderType,
      tableNumber: state.orderType === 'dine-in' ? $('#tableNumber').value.trim() : '',
      items,
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      status: 'pending',
      payment: null,
      cashier: state.user ? state.user.name : 'kasir',
      note: ($('#cartNoteInput')?.value || '').trim()
    };
    state.pendingOrders.push(order);
    state.cart = [];
    $('#discountInput').value = '0';
    $('#tableNumber').value = '';
    const noteInput = $('#cartNoteInput');
    if (noteInput) noteInput.value = '';
    savePending();
    renderProducts();
    renderCart();
    renderQueues();
    showToast(`Pesanan ${order.id} disimpan (belum dibayar). Lanjutkan lewat tab "Bayar nanti".`);
  }

  function resumePendingOrder(orderId) {
    const order = state.pendingOrders.find((pending) => pending.id === orderId);
    if (!order) return;
    const items = order.items.filter((item) => state.products.some((product) => product.id === item.productId));
    const missing = order.items.length - items.length;
    if (!items.length) {
      // JANGAN dihapus diam-diam. Kasir memutuskan: kembalikan menunya atau batalkan pesanan.
      closeModal();
      renderQueues();
      showToast(`Pesanan ${order.id} memakai menu yang sudah tidak ada. Pesanan tetap tersimpan — kembalikan menunya atau batalkan pesanan.`, 7000);
      return;
    }
    removePendingOrder(orderId);
    state.orderType = order.orderType;
    state.cart = items.map((item) => ({ productId: item.productId, qty: item.qty, name: item.name, price: item.price, emoji: '', note: (item.note || '').trim() }));
    const tableNumberInput = $('#tableNumber');
    if (tableNumberInput) tableNumberInput.value = order.tableNumber || '';
    const discountInput = $('#discountInput');
    if (discountInput) discountInput.value = order.discount || '0';
    const noteInput = $('#cartNoteInput');
    if (noteInput) noteInput.value = order.note || '';
    renderProducts();
    renderCart();
    switchCartTab('cart');
    closeModal();
    openCheckout();
    showToast(
      missing
        ? `Pesanan ${order.id} dimuat. ${missing} menu sudah tidak ada di daftar menu dan tidak ikut dimuat.`
        : `Pesanan ${order.id} dimuat kembali untuk pembayaran.`,
      missing ? 6500 : 3200
    );
  }

  function finishPendingOrder(orderId) {
    const order = state.pendingOrders.find((pending) => pending.id === orderId);
    if (!order) return;
    removePendingOrder(orderId);
    renderQueues();
    closeModal();
    showToast(`Pesanan ${order.id} selesai dibuat.`);
  }

  function cancelPendingOrder(orderId) {
    const order = state.pendingOrders.find((pending) => pending.id === orderId);
    if (!order) return;
    const paid = order.status === 'preparing';
    const message = paid
      ? `Batalkan pesanan ${order.id}? Pesanan sudah dibayar dan akan dihapus dari antrean tanpa masuk riwayat penjualan.`
      : `Batalkan pesanan ${order.id}? Data keranjang/riwayat tidak akan tersimpan.`;
    if (!window.confirm(message)) return;
    removePendingOrder(orderId);
    renderQueues();
    closeModal();
    showToast('Pesanan dibatalkan.');
  }

  function advanceOnlineOrder(orderId) {
    const order = state.onlineOrders.find((online) => online.id === orderId);
    if (!order) return;
    if (!resolveOnlineOrderItems(order.items).length) {
      showToast('Item pesanan tidak ditemukan di menu. Perbarui menu dulu.');
      return;
    }
    const next = { baru: 'dibuat', dibuat: 'siap', siap: 'selesai' }[order.status];
    if (!next) return;
    order.status = next;
    if (next === 'siap') order.pickupCode = makePickupCode(order);
    if (next === 'selesai') {
      removeOnlineOrder(orderId);
      const completed = buildCompletedOnlineOrder(order);
      state.orders.push(completed);
      deductPortionStock(completed);
      saveAll();
      noteOrderSaved();
      renderDashboard();
      renderProducts();
      renderCart();
      renderMenuTable();
      renderReports();
      renderQueues();
      closeModal();
      showToast(`Pesanan ${order.code} selesai & tercatat di laporan.`);
      return;
    }
    saveOnline();
    renderQueues();
    if (state.orderDetailTarget && state.orderDetailTarget.id === orderId) renderOrderDetail('online', orderId);
    showToast(`Pesanan ${order.code} ${next === 'dibuat' ? 'diterima' : 'siap diambil'}.`);
  }

  function buildCompletedOnlineOrder(order) {
    const items = resolveOnlineOrderItems(order.items);
    const subtotal = items.reduce((sum, item) => sum + item.total, 0);
    return {
      id: `ONL-${order.code || String(Date.now()).slice(-5)}`,
      createdAt: new Date().toISOString(),
      items,
      orderType: 'online',
      tableNumber: '',
      subtotal,
      discount: 0,
      total: subtotal,
      taxRate: state.settings.taxRate,
      taxIncluded: true,
      payment: ONLINE_PLATFORMS[order.source] ? order.source : 'other',
      paidAmount: subtotal,
      changeAmount: 0,
      status: 'paid',
      cashier: state.user.name,
      onlineCode: order.code || '',
      onlineCustomer: order.customer || ''
    };
  }

  function cancelOnlineOrder(orderId) {
    const order = state.onlineOrders.find((online) => online.id === orderId);
    if (!order) return;
    const platform = ONLINE_PLATFORMS[order.source] || ONLINE_PLATFORMS.other;
    state.onlineRejectOrderId = orderId;
    const input = $('#onlineRejectReasonInput');
    input.value = state.settings.onlineRejectionMessage || DEFAULT_SETTINGS.onlineRejectionMessage;
    $('#onlineRejectOrderLabel').textContent = `${order.code || order.id} · ${platform.label}`;
    openModal('onlineRejectReasonModal');
  }

  async function submitOnlineRejection(event) {
    event.preventDefault();
    const orderId = state.onlineRejectOrderId;
    const order = state.onlineOrders.find((online) => online.id === orderId);
    if (!order) { closeModal(); return; }
    const reasonText = ($('#onlineRejectReasonInput').value || '').trim() || DEFAULT_SETTINGS.onlineRejectionMessage;
    const submit = $('#onlineRejectSubmit');
    submit.disabled = true;
    try {
      if (order.source === 'gofood' && apiBaseUrl() && apiToken()) {
        await apiRequest('/api/online/orders/' + encodeURIComponent(order.id) + '/aksi', {
          method: 'POST',
          body: JSON.stringify({ action: 'reject', reasonText })
        });
      }
    } catch (error) {
      showToast(error.message || 'Alasan penolakan gagal dikirim ke server.');
      submit.disabled = false;
      return;
    }
    const isNew = order.status === 'baru';
    removeOnlineOrder(orderId);
    saveOnline();
    renderQueues();
    closeModal();
    state.onlineRejectOrderId = null;
    submit.disabled = false;
    if (state.orderDetailTarget && state.orderDetailTarget.id === orderId) state.orderDetailTarget = null;
    showToast(isNew ? `Pesanan ${order.code} ditolak.` : `Pesanan ${order.code} dibatalkan.`);
  }

  // Hapus hanya entri pertama dengan id tersebut (id kembar tidak ikut hilang)
  function removeOnlineOrder(orderId) {
    const index = state.onlineOrders.findIndex((online) => online.id === orderId);
    if (index === -1) return false;
    state.onlineOrders.splice(index, 1);
    saveOnline();
    return true;
  }

  function openOrderDetail(kind, orderId) {
    const order = kind === 'pending'
      ? state.pendingOrders.find((pending) => pending.id === orderId)
      : normalizeOnlineOrder(state.onlineOrders.find((online) => online.id === orderId));
    if (!order) return;
    state.orderDetailTarget = { kind, id: order.id };
    renderOrderDetail(kind, orderId);
    openModal('orderModal');
  }

  function renderOrderDetail(kind, orderId) {
    const order = kind === 'pending'
      ? state.pendingOrders.find((pending) => pending.id === orderId)
      : normalizeOnlineOrder(state.onlineOrders.find((online) => online.id === orderId));
    if (!order) return;
    const body = $('#orderDetailBody');
    const footer = $('#orderModalFooter');
    const kicker = $('#orderModalKicker');
    const title = $('#orderModalTitle');
    if (kicker) kicker.textContent = kind === 'pending' ? 'Pesanan dibuat' : 'Pesanan online';
    if (title) title.textContent = kind === 'pending' ? 'Detail pesanan dibuat' : 'Detail pesanan online';
    let metaHtml = '';
    if (kind === 'pending') {
      const unpaid = order.status !== 'preparing';
      metaHtml = `<div class="order-detail-meta"><span class="status-pill ${unpaid ? 'pending' : 'available'}">${unpaid ? 'Belum dibayar' : 'Sudah dibayar · masih dibuat'}</span><strong>${escapeHtml(order.id)}</strong><small>${formatDateTime(order.createdAt)} · ${escapeHtml(orderTypeLabel(order.orderType))}${order.tableNumber ? ` · Meja ${escapeHtml(order.tableNumber)}` : ''}</small></div>`;
    } else {
      const platform = ONLINE_PLATFORMS[order.source] || ONLINE_PLATFORMS.other;
      metaHtml = `<div class="order-detail-meta"><span class="status-pill ${ONLINE_STATUS_CLASS[order.status] || 'pending'}">${ONLINE_STATUS[order.status] || order.status}</span><strong>${escapeHtml(platform.label)} · ${escapeHtml(order.code)}</strong><small>${formatDateTime(order.createdAt)}${order.customer ? ` · Pelanggan ${escapeHtml(order.customer)}` : ''}</small></div>`;
    }
    const itemRows = orderItems(order).map((item) => {
      const itemNote = (item.note || '').trim();
      const noteLi = itemNote ? `<li class="order-detail-item-note">📝 ${escapeHtml(itemNote)}</li>` : '';
      return `<li><span>${item.qty}× ${escapeHtml(item.name)}</span><b>${formatRupiah(item.total)}</b></li>${noteLi}`;
    }).join('');
    const discountRow = Number(order.discount) > 0 ? `<li class="order-detail-discount"><span>Diskon</span><b>-${formatRupiah(order.discount)}</b></li>` : '';
    let pickupHtml = '';
    if (order.status === 'siap' && order.pickupCode) {
      const isCode4 = order.source === 'gofood' || order.source === 'grab';
      pickupHtml = `<div class="pickup-code-block"><small>${isCode4 ? 'Kode unik GoFood/Grab (dummy)' : 'Nomor pesanan'}</small><strong>${escapeHtml(order.pickupCode)}</strong><small>${isCode4 ? 'Kode 4 digit yang disebut kurir saat menyerahkan pesanan' : 'Dipakai kurir sebagai referensi pengambilan'}</small></div>`;
    }
    const noteHtml = order.note ? `<p class="order-detail-note">📝 Catatan: ${escapeHtml(order.note)}</p>` : '';
    body.innerHTML = `${metaHtml}<div class="order-detail-items"><ul>${itemRows}${discountRow}</ul><div class="order-detail-total"><span>Total</span><strong>${formatRupiah(order.total)}</strong></div></div>${pickupHtml}${noteHtml}`;
    let buttons = '';
    if (kind === 'pending') {
      if (order.status === 'pending') {
        buttons = `<button class="secondary-button" type="button" data-action="cancel-pending" data-order-id="${escapeAttr(order.id)}">Batalkan</button><button class="primary-button" type="button" data-action="resume-pending" data-order-id="${escapeAttr(order.id)}">Lanjutkan ke pembayaran <span>→</span></button>`;
      } else {
        // Sudah dibayar: kasir sering lupa mencetak struk saat transaksi —
        // sediakan cetak ulang langsung dari sini (human error lupa print di awal).
        // Batalkan diletakkan tepat di kiri "Tandai selesai" agar mudah ditemukan.
        buttons = `<button class="secondary-button" type="button" data-action="reprint-order" data-order-id="${escapeAttr(order.id)}">🖨 Cetak struk</button><button class="danger-button" type="button" data-action="cancel-pending" data-order-id="${escapeAttr(order.id)}">🚫 Batalkan pesanan</button><button class="primary-button" type="button" data-action="finish-pending" data-order-id="${escapeAttr(order.id)}">✓ Tandai selesai dibuat</button>`;
      }
    } else {
      const actionMap = {
        baru: { label: '✅ Terima pesanan', cls: 'success-button' },
        dibuat: { label: '🛵 Siap diambil', cls: 'primary-button' },
        siap: { label: '🏁 Selesai diambil', cls: 'success-button' }
      }[order.status];
      // v12: cetak = struk pelanggan (bukan nota dapur), tetap ada di semua tahap.
      // "Batalkan pesanan" ditaruh di UJUNG KIRI dan selalu ada (termasuk saat
      // "Siap diambil") supaya salah tekan status bisa segera dibatalkan.
      buttons = `<button class="danger-button order-cancel-left" type="button" data-action="cancel-online" data-order-id="${escapeAttr(order.id)}">🚫 Batalkan pesanan</button>`;
      buttons += `<button class="secondary-button" type="button" data-action="print-online-ticket" data-order-id="${escapeAttr(order.id)}">🖨 Cetak struk</button>`;
      if (actionMap) buttons += `<button class="${actionMap.cls}" type="button" data-action="advance-online" data-order-id="${escapeAttr(order.id)}">${escapeHtml(actionMap.label)}</button>`;
    }
    footer.innerHTML = buttons;
  }

  function matchesMenuFilter(product, filter) {
    if (filter === 'all') return true;
    const availability = getProductAvailability(product, true);
    if (filter === 'available') return availability.statusClass === 'available';
    if (filter === 'low') return availability.statusClass === 'pending';
    if (filter === 'unavailable') return availability.statusClass === 'unavailable';
    return true;
  }

  function renderMenuSummary() {
    const summaryEl = $('#menuSummary');
    if (!summaryEl) return;
    const counts = { available: 0, low: 0, unavailable: 0 };
    state.products.forEach((product) => {
      const statusClass = getProductAvailability(product, true).statusClass;
      if (statusClass === 'available') counts.available += 1;
      else if (statusClass === 'pending') counts.low += 1;
      else counts.unavailable += 1;
    });
    summaryEl.innerHTML = `<div class="menu-summary-card"><span class="menu-summary-icon">▤</span><span><strong>${formatNumber(state.products.length)}</strong><small>menu terdaftar</small></span></div><div class="menu-summary-card"><span class="menu-summary-icon">✓</span><span><strong>${formatNumber(counts.available)}</strong><small>bisa dijual</small></span></div><div class="menu-summary-card"><span class="menu-summary-icon">!</span><span><strong>${formatNumber(counts.low)}</strong><small>stok menipis</small></span></div><div class="menu-summary-card"><span class="menu-summary-icon">✕</span><span><strong>${formatNumber(counts.unavailable)}</strong><small>habis / nonaktif</small></span></div>`;
  }

  function renderMenuTable() {
    renderMenuSummary();
    const query = ($('#menuTableSearch')?.value || '').trim().toLowerCase();
    const products = state.products.filter((product) => (!query || `${product.name} ${product.category}`.toLowerCase().includes(query)) && matchesMenuFilter(product, state.menuFilter));
    const countLabel = $('#menuCountLabel');
    if (countLabel) countLabel.textContent = products.length === state.products.length ? `${formatNumber(products.length)} menu` : `${formatNumber(products.length)} dari ${formatNumber(state.products.length)} menu`;
    const list = $('#menuList');
    if (!list) return;
    // v13: katalog menu berupa daftar memanjang — satu menu satu baris — di HP
    // maupun tablet. Tiap baris memakai grid tiga lajur tetap supaya lurus.
    list.innerHTML = products.length ? products.map(menuRowMarkup).join('') : `<p class="menu-list-empty">${query ? 'Menu tidak ditemukan.' : 'Tidak ada menu pada filter ini.'}</p>`;
  }

  function menuRowMarkup(product) {
    const availability = getProductAvailability(product, true);
    const limited = product.stock !== null && product.stock !== undefined && Number.isFinite(Number(product.stock));
    const stockText = limited ? `Sisa ${formatNumber(Math.max(0, Number(product.stock)))}` : 'Tanpa batas';
    const categoryName = `${categoryEmoji(product.category)} ${categoryLabel(product.category)}`.trim();
    return `<article class="menu-row">
      <span class="menu-row-emoji" aria-hidden="true">${escapeHtml(product.emoji || '🍽️')}</span>
      <div class="menu-row-body">
        <strong class="menu-row-name">${escapeHtml(product.name)}</strong>
        <small class="menu-row-desc">${escapeHtml(product.description || 'Tanpa deskripsi')}</small>
        <span class="menu-row-meta"><span class="menu-row-cat">${escapeHtml(categoryName || '—')}</span><span class="menu-row-dot" aria-hidden="true">·</span><span class="menu-row-stock">${escapeHtml(stockText)}</span></span>
      </div>
      <div class="menu-row-side">
        <b class="menu-row-price">${formatRupiah(product.price)}</b>
        <span class="status-pill ${availability.statusClass}">${availability.statusLabel}</span>
        <div class="menu-row-actions">
          <button class="row-action" type="button" data-toggle-product="${escapeAttr(product.id)}" title="${product.available ? 'Nonaktifkan menu' : 'Aktifkan menu'}" aria-label="${product.available ? 'Nonaktifkan' : 'Aktifkan'} menu ${escapeAttr(product.name)}">${product.available ? '◉' : '○'}</button>
          <button class="row-action" type="button" data-edit-product="${escapeAttr(product.id)}" title="Edit menu" aria-label="Edit menu ${escapeAttr(product.name)}">✎</button>
          <button class="row-action danger" type="button" data-delete-product="${escapeAttr(product.id)}" title="Hapus menu" aria-label="Hapus menu ${escapeAttr(product.name)}">×</button>
        </div>
      </div>
    </article>`;
  }

  function openProductModal(productId = null) {
    state.editingProductId = productId;
    const form = $('#productForm');
    form.reset();
    $('#productId').value = productId || '';
    if (productId) {
      const product = state.products.find((item) => item.id === productId);
      if (!product) return;
      $('#productModalTitle').textContent = 'Edit menu';
      $('#productName').value = product.name;
      $('#productCategory').value = product.category;
      $('#productPrice').value = product.price;
      $('#productStock').value = product.stock === null || product.stock === undefined ? '' : product.stock;
      $('#productDescription').value = product.description || '';
    } else {
      $('#productModalTitle').textContent = 'Tambah menu';
    }
    openModal('productModal');
  }

  function handleProductSubmit(event) {
    event.preventDefault();
    const id = $('#productId').value || uid('menu');
    const category = $('#productCategory').value;
    const existing = state.products.find((item) => item.id === id);
    const stockInput = $('#productStock').value.trim();
    const name = $('#productName').value.trim();
    if (!name) {
      $('#productName').setCustomValidity('Nama menu tidak boleh kosong');
      $('#productName').reportValidity();
      return;
    }
    $('#productName').setCustomValidity('');
    const product = {
      id,
      name,
      category,
      price: Math.max(0, Number($('#productPrice').value) || 0),
      stock: stockInput === '' ? null : Math.max(0, Number(stockInput) || 0),
      description: $('#productDescription').value.trim(),
      available: existing ? existing.available : true,
      emoji: existing ? existing.emoji : (category === 'minuman' ? '🥤' : category === 'topping' ? '🍢' : '🍜')
    };
    if (existing) Object.assign(existing, product);
    else state.products.push(product);
    saveAll();
    renderProducts();
    renderMenuTable();
    closeModal();
    showToast(existing ? 'Menu berhasil diperbarui.' : 'Menu baru berhasil ditambahkan.');
  }

  function deleteProduct(productId) {
    const product = state.products.find((item) => item.id === productId);
    if (!product) return;
    if (!window.confirm(`Hapus menu "${product.name}"?`)) return;
    state.products = state.products.filter((item) => item.id !== productId);
    state.cart = state.cart.filter((item) => item.productId !== productId);
    saveAll();
    renderProducts();
    renderMenuTable();
    renderCart();
    showToast('Menu dihapus dari katalog.');
  }

  function toggleProductAvailability(productId) {
    const product = state.products.find((item) => item.id === productId);
    if (!product) return;
    product.available = !product.available;
    if (!product.available) state.cart = state.cart.filter((item) => item.productId !== productId);
    save(STORAGE_KEYS.products, state.products);
    renderMenuTable();
    renderProducts();
    renderCart();
    showToast(`${product.name} ${product.available ? 'diaktifkan' : 'dinonaktifkan'}.`);
  }

  function isDateKey(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return false;
    const [year, month, day] = value.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
  }

  function updateReportDateLimits() {
    const from = $('#reportFrom').value;
    const to = $('#reportTo').value;
    $('#reportTo').min = from || '';
    $('#reportFrom').max = to || '';
    $('#reportRangeError').hidden = true;
    $('#reportRangeError').textContent = '';
  }

  function getReportRange() {
    const from = $('#reportFrom').value || dateKey();
    const to = $('#reportTo').value || dateKey();
    const error = $('#reportRangeError');
    if (!isDateKey(from) || !isDateKey(to)) {
      error.textContent = 'Masukkan tanggal yang valid.';
      error.hidden = false;
      return null;
    }
    if (from > to) {
      error.textContent = 'Tanggal awal tidak boleh lebih besar dari tanggal akhir.';
      error.hidden = false;
      return null;
    }
    error.hidden = true;
    error.textContent = '';
    return { from, to };
  }

  function getFilteredReportOrders(from, to) {
    return state.orders.filter((order) => {
      const key = orderDate(order);
      return (!order.status || order.status === 'paid') && key >= from && key <= to;
    });
  }

  function applyQuickRange(preset) {
    const today = new Date();
    let from = new Date(today);
    let to = new Date(today);
    if (preset === 'yesterday') {
      from = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
      to = new Date(from);
    }
    if (preset === '7') from.setDate(from.getDate() - 6);
    if (preset === '30') from.setDate(from.getDate() - 29);
    if (preset === 'month') from.setDate(1);
    const fromInput = $('#reportFrom');
    const toInput = $('#reportTo');
    if (!fromInput || !toInput) return;
    fromInput.value = dateKey(from);
    toInput.value = dateKey(to);
    renderReports();
  }

  // Awal/akhir minggu (Senin–Minggu) untuk laporan mingguan.
  function startOfWeek(date = new Date()) {
    const day = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const offset = (day.getDay() + 6) % 7; // 0 = Senin
    day.setDate(day.getDate() - offset);
    return day;
  }

  function endOfWeek(date = new Date()) {
    const end = startOfWeek(date);
    end.setDate(end.getDate() + 6);
    return end;
  }

  function setReportRange(fromDate, toDate) {
    const fromInput = $('#reportFrom');
    const toInput = $('#reportTo');
    if (fromInput) fromInput.value = dateKey(fromDate);
    if (toInput) toInput.value = dateKey(toDate);
  }

  // Label periode yang membedakan "hari ini" dan "minggu ini" dari rentang bebas.
  function reportPeriodText(from, to) {
    const today = dateKey();
    const yesterdayDate = new Date();
    yesterdayDate.setDate(yesterdayDate.getDate() - 1);
    const yesterday = dateKey(yesterdayDate);
    const weekFrom = dateKey(startOfWeek(new Date()));
    const weekTo = dateKey(endOfWeek(new Date()));
    if (from === to && from === today) return `Hari ini • ${formatShortDate(from)}`;
    if (from === to && from === yesterday) return `Kemarin • ${formatShortDate(from)}`;
    if (from === to) return `${formatShortDate(from)} • 1 hari`;
    if (from === weekFrom && to === weekTo) return `Minggu ini • ${formatShortDate(from)} – ${formatShortDate(to)}`;
    const totalDays = Math.max(1, Math.round((new Date(`${to}T00:00:00`) - new Date(`${from}T00:00:00`)) / 86400000) + 1);
    return `${formatShortDate(from)} – ${formatShortDate(to)} • ${formatNumber(totalDays)} hari`;
  }

  function renderReports() {
    const range = getReportRange();
    if (!range) return;
    const { from, to } = range;
    const filtered = getFilteredReportOrders(from, to);
    const revenue = filtered.reduce((sum, order) => sum + Number(order.total || 0), 0);
    const itemCount = filtered.reduce((sum, order) => sum + orderItems(order).reduce((itemSum, item) => itemSum + Number(item.qty || 0), 0), 0);
    $('#reportRevenue').textContent = formatRupiah(revenue);
    $('#reportOrders').textContent = formatNumber(filtered.length);
    $('#reportItems').textContent = formatNumber(itemCount);
    $('#reportAverage').textContent = formatRupiah(filtered.length ? revenue / filtered.length : 0);
    const periodLabel = $('#reportPeriodLabel');
    if (periodLabel) periodLabel.textContent = reportPeriodText(from, to);

    const recent = [...filtered].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    const listEl = $('#reportRecentList');
    if (listEl) {
      listEl.innerHTML = recent.length ? recent.map((order) => {
        const items = orderItems(order).map((item) => `${item.qty}× ${item.name}`).join(', ');
        // v12: pemilik boleh menghapus transaksi (miss pembayaran) — tombolnya
        // diletakkan tepat di sebelah tombol struk. Kasir tidak melihat tombol ini.
        const rowActions = `<button class="row-action" type="button" data-action="reprint-order" data-order-id="${escapeHtml(order.id)}" title="Cetak ulang struk ${escapeHtml(order.id)}" aria-label="Cetak ulang struk ${escapeHtml(order.id)}">▤</button>${isOwnerUser() ? `<button class="row-action danger" type="button" data-action="delete-order" data-order-id="${escapeHtml(order.id)}" title="Hapus transaksi ${escapeHtml(order.id)} dari laporan" aria-label="Hapus transaksi ${escapeHtml(order.id)} dari laporan">🗑</button>` : ''}`;
        return `<tr><td data-label="Waktu"><span class="report-date">${escapeHtml(formatShortDate(orderDate(order)))}</span><span class="report-time">${escapeHtml(formatTime(order.createdAt))}</span></td><td data-label="No. transaksi"><span class="order-number">${escapeHtml(order.id)}</span></td><td data-label="Pesanan" title="${escapeHtml(items)}">${escapeHtml(items)}</td><td data-label="Pembayaran"><span class="payment-badge ${escapeHtml(order.payment)}">${paymentLabel(order.payment)}</span></td><td data-label="Total" class="align-right"><strong>${formatRupiah(order.total)}</strong></td><td data-label="Struk" class="align-right"><span class="row-actions">${rowActions}</span></td></tr>`;
      }).join('') : '<tr><td colspan="6" class="empty-cell">Belum ada transaksi pada periode ini.</td></tr>';
    }
    const note = $('#reportRecentNote');
    if (note) note.textContent = recent.length ? `${formatNumber(recent.length)} transaksi ditampilkan` : '—';
  }

  function exportReportPreset(kind) {
    const today = new Date();
    if (kind === 'today') setReportRange(today, today);
    else if (kind === 'week') setReportRange(startOfWeek(today), endOfWeek(today));
    exportReport(kind);
  }

  function exportReport(kind) {
    renderReports();
    const range = getReportRange();
    if (!range) return;
    const isToday = range.from === range.to;
    const kindLabel = kind === 'today' || (kind === undefined && isToday) ? 'Harian' : kind === 'week' ? 'Mingguan' : 'Rentang';
    const title = kindLabel === 'Mingguan' ? 'LAPORAN PENJUALAN MINGGUAN' : kindLabel === 'Harian' ? 'LAPORAN PENJUALAN HARIAN' : 'LAPORAN PENJUALAN';
    const orders = getFilteredReportOrders(range.from, range.to).sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
    const slug = kindLabel === 'Mingguan' ? 'mingguan' : kindLabel === 'Harian' ? 'harian' : 'rentang';
    const filename = `mpj-laporan-${slug}-${range.from}-${range.to}.xlsx`;
    try {
      const bytes = buildReportXlsx(range, orders, title, kindLabel);
      if (isNativeApp()) {
        exportShareNative(filename, bytes);
      } else {
        downloadFile(filename, bytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        showToast(`Laporan Excel diunduh: ${filename}`);
      }
    } catch (error) {
      showToast(`Laporan Excel gagal dibuat (${(error && error.message) || 'kesalahan'}).`, 6000);
    }
  }

  function exportData() {
    const backup = buildBackupPayload();
    save(STORAGE_KEYS.lastExport, new Date().toISOString());
    downloadFile(`mpj-backup-${dateKey()}.json`, JSON.stringify(backup, null, 2), 'application/json');
    renderSnapshotList();
    showToast('Backup JSON berhasil dibuat — simpan ke Google Drive.');
  }

  function importDataFile(event) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const data = JSON.parse(reader.result);
        if (!Array.isArray(data.products) || !Array.isArray(data.orders)) throw new Error('Format tidak valid');
        takeSnapshot('Cadangan sebelum import');
        applyBackupPayload(data);
        showToast('Backup berhasil diimpor.');
      } catch (error) {
        showToast('File backup tidak valid.');
      }
    };
    reader.readAsText(file);
  }

  function restoreSnapshot(snapshotId) {
    const list = load([], STORAGE_KEYS.snapshots);
    const snapshot = list.find((item) => item.id === snapshotId);
    if (!snapshot) {
      showToast('Cadangan tidak ditemukan.');
      renderSnapshotList();
      return;
    }
    if (!window.confirm(`Kembalikan data ke cadangan ${formatDateTime(snapshot.at)}?\nData transaksi setelah titik itu akan hilang dari layar (kondisi sebelum dikembalikan tetap disimpan sebagai cadangan lokal).`)) return;
    takeSnapshot('Cadangan sebelum kembalikan');
    applyBackupPayload(snapshot.data);
    showToast('Data dikembalikan dari cadangan.');
  }

  // Hapus SATU cadangan saja — cadangan lain dan data POS yang sedang dipakai
  // tidak disentuh.
  function deleteSnapshot(snapshotId) {
    const list = load([], STORAGE_KEYS.snapshots);
    const index = list.findIndex((item) => item.id === snapshotId);
    if (index === -1) {
      showToast('Cadangan tidak ditemukan.');
      renderSnapshotList();
      return;
    }
    const snapshot = list[index];
    if (!window.confirm(`Hapus cadangan ${formatDateTime(snapshot.at)} (${snapshot.reason})?\nHanya cadangan ini yang dihapus — data POS yang sedang dipakai tidak berubah.`)) return;
    list.splice(index, 1);
    if (!writeKey(STORAGE_KEYS.snapshots, JSON.stringify(list))) {
      showToast('Cadangan gagal dihapus. Coba lagi.');
      return;
    }
    renderSnapshotList();
    showToast('Cadangan dihapus.');
  }

  function takeSnapshotNow() {
    const snapshot = takeSnapshot('Manual');
    renderSnapshotList();
    showToast(snapshot ? 'Cadangan lokal tersimpan di perangkat.' : 'Penyimpanan penuh — cadangan otomatis dilewati, data utama tetap aman.');
  }

  /* Bersihkan riwayat pembelian di PERANGKAT INI: transaksi selesai, antrean
     "Dibuat", dan pesanan online. Menu, kategori, pengaturan, dan keranjang
     tidak disentuh. Karena sinkron berjalan, entri yang dibersihkan juga ikut
     dihapus dari database bersama lewat penanda hapus (batu nisan). */
  function clearTransactionHistory() {
    const jumlah = state.orders.length + state.pendingOrders.length + state.onlineOrders.length;
    if (!jumlah) { showToast('Riwayat pembelian sudah kosong.'); return; }
    const yakin = window.confirm(
      `Hapus SEMUA riwayat pembelian di perangkat ini? (${jumlah} entri: transaksi, Pesanan dibuat, dan Online)\n\n` +
      'Menu, kategori, pengaturan, dan keranjang TIDAK ikut terhapus. ' +
      'File backup dan cadangan snapshot juga tetap aman — hapus manual kalau mau bersih total.'
    );
    if (!yakin) return;
    state.orders = [];
    state.pendingOrders = [];
    state.onlineOrders = [];
    save(STORAGE_KEYS.orders, state.orders);
    save(STORAGE_KEYS.pending, state.pendingOrders);
    save(STORAGE_KEYS.online, state.onlineOrders);
    renderAll();
    showToast(`Riwayat pembelian dibersihkan (${jumlah} entri dihapus).`);
  }

  function renderAll() {
    renderCategoryTabs();
    renderCategoryOptions();
    renderDashboard();
    renderProducts();
    renderCart();
    renderQueues();
    renderMenuTable();
    renderReports();
    updateBusinessLabels();
    hydrateSettingsForm();
  }

  function openModal(id) {
    $$('.modal').forEach((modal) => { modal.hidden = true; });
    const modal = $(`#${id}`);
    if (!modal) return;
    $('#modalBackdrop').hidden = false;
    modal.hidden = false;
    document.body.style.overflow = 'hidden';
    const focusTarget = $('[data-initial-focus]', modal) || $('input, select, textarea, button', modal);
    // preventScroll: fokus ke elemen di atas modal tidak boleh menggulirkan
    // isi modal (pernah mereset auto-scroll QRIS ke 0 ~30ms setelah diklik).
    if (focusTarget) window.setTimeout(() => focusTarget.focus({ preventScroll: true }), 30);
  }

  function closeModal() {
    $$('.modal').forEach((modal) => { modal.hidden = true; modal.classList.remove('is-open'); });
    const backdrop = $('#modalBackdrop');
    if (backdrop) backdrop.hidden = true;
    document.body.style.overflow = '';
    state.orderDetailTarget = null;
    state.onlineRejectOrderId = null;
  }

  function showToast(message, duration = 3200) {
    const toast = elSafe('#toast');
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add('is-visible');
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => toast.classList.remove('is-visible'), duration);
  }

  function paymentLabel(payment) { return ({ cash: 'Tunai', qris: 'QRIS', transfer: 'Transfer', card: 'Kartu', gofood: 'GoFood', shopee: 'ShopeeFood', grab: 'GrabFood', maxim: 'Maxim', other: 'Online', online: 'Online' })[payment] || payment || ''; }
  function orderTypeLabel(value) { return value === 'dine-in' ? 'Makan di tempat' : value === 'takeaway' ? 'Bawa pulang' : value === 'delivery' ? 'Delivery' : value === 'online' ? 'Online' : value; }
  function categoryLabel(category) {
    const found = (state.categories || []).find((entry) => entry.id === category);
    if (found) return found.label;
    return ({ mie: 'Mie', [CAT_MENU_PANGSIT]: 'Mie Pangsit Jakarta', [CAT_MIE_KERING]: 'Mie Kering', [CAT_SPECIAL]: 'Special menu', minuman: 'Minuman', topping: 'Topping' })[category] || category || 'Lainnya';
  }

  function categoryEmoji(category) {
    const found = (state.categories || []).find((entry) => entry.id === category);
    if (found && found.emoji) return found.emoji;
    return '';
  }

  function renderCategoryTabs() {
    const tabs = $('#categoryTabs');
    if (!tabs) return;
    if (state.category !== 'semua' && !state.categories.some((category) => category.id === state.category)) state.category = 'semua';
    const chips = [{ id: 'semua', label: 'Semua', emoji: '🍽️' }, ...normalizeCategories(state.categories)];
    tabs.innerHTML = chips.map((chip) => `<button class="${chip.id === state.category ? 'is-active' : ''}" type="button" data-category="${escapeAttr(chip.id)}" aria-pressed="${chip.id === state.category}"><span class="category-tab-emoji" aria-hidden="true">${escapeHtml(chip.emoji)}</span>${escapeHtml(chip.label)}</button>`).join('');
  }

  function renderCategoryOptions() {
    const select = $('#productCategory');
    if (!select) return;
    select.innerHTML = normalizeCategories(state.categories).map((category) => `<option value="${escapeAttr(category.id)}">${escapeHtml(category.emoji)} ${escapeHtml(category.label)}</option>`).join('');
  }

  /* Isi dropdown emoji kategori: daftar polos tanpa keterangan — hanya emoji.
     Opsi pertama 🔄 = "Otomatis", POS menebak emoji dari nama kategori. */
  function renderEmojiSelect(select, selected) {
    if (!select) return;
    const value = normalizeEmoji(selected || '');
    // emoji hasil impor/ketik manual yang tidak ada di daftar tetap ditampilkan
    const custom = value && !CATEGORY_EMOJI_CHOICES.includes(value) ? `<option value="${escapeAttr(value)}">${escapeHtml(value)}</option>` : '';
    select.innerHTML = `<option value="">${EMOJI_AUTO_ICON}</option>${CATEGORY_EMOJI_CHOICES.map((emoji) => `<option value="${escapeAttr(emoji)}">${escapeHtml(emoji)}</option>`).join('')}${custom}`;
    select.value = value;
  }

  function renderCategoryManager() {
    const list = $('#categoryList');
    if (!list) return;
    state.categories = normalizeCategories(state.categories);
    list.innerHTML = state.categories.length ? state.categories.map((category) => {
      const used = state.products.filter((product) => product.category === category.id).length;
      return `<div class="category-row"><select class="category-emoji-select" data-category-emoji="${escapeAttr(category.id)}" aria-label="Emoji kategori ${escapeAttr(category.label)}" title="Pilih emoji — 🔄 berarti tebak otomatis dari nama kategori"></select><input class="category-name-input" type="text" maxlength="24" value="${escapeAttr(category.label)}" data-category-input="${escapeAttr(category.id)}" aria-label="Nama kategori ${escapeAttr(category.label)}" /><span class="category-count">${formatNumber(used)} menu</span><button class="row-action danger" type="button" data-delete-category="${escapeAttr(category.id)}" title="${used ? 'Kategori dipakai menu — pindahkan dulu' : 'Hapus kategori'}" aria-label="Hapus kategori ${escapeAttr(category.label)}" ${used ? 'disabled' : ''}>×</button></div>`;
    }).join('') : '<p class="empty-cell">Belum ada kategori — tambahkan lewat form di atas.</p>';
    $$('#categoryList .category-name-input').forEach((input) => {
      input.addEventListener('change', () => renameCategory(input.dataset.categoryInput, input.value));
    });
    $$('#categoryList .category-emoji-select').forEach((select) => {
      const category = state.categories.find((entry) => entry.id === select.dataset.categoryEmoji);
      renderEmojiSelect(select, category ? category.emoji : '');
      select.addEventListener('change', () => updateCategoryEmoji(select.dataset.categoryEmoji, select.value));
    });
  }

  function openCategoryModal(focusAdd = false) {
    renderCategoryManager();
    renderEmojiSelect($('#newCategoryEmoji'), $('#newCategoryEmoji')?.value || '');
    openModal('categoryModal');
    if (focusAdd) window.setTimeout(() => { const input = $('#newCategoryName'); if (input) input.focus(); }, 60);
  }

  function slugCategoryId(label) {
    const base = label.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'kategori';
    let id = base;
    let counter = 2;
    while (state.categories.some((category) => category.id === id)) id = `${base}-${counter++}`;
    return id;
  }

  function addCategory() {
    const input = $('#newCategoryName');
    if (!input) return null;
    const label = String(input.value || '').trim().slice(0, 24);
    if (!label) { showToast('Tulis nama kategori dulu.'); input.focus(); return null; }
    if (state.categories.some((category) => category.label.toLowerCase() === label.toLowerCase())) { showToast('Kategori dengan nama itu sudah ada.'); return null; }
    const emojiSelect = $('#newCategoryEmoji');
    const emoji = normalizeEmoji(emojiSelect ? emojiSelect.value : '') || guessCategoryEmoji(label);
    const category = { id: slugCategoryId(label), label, emoji };
    state.categories.push(category);
    save(STORAGE_KEYS.categories, state.categories);
    input.value = '';
    if (emojiSelect) emojiSelect.value = ''; // kembali ke "Otomatis"
    renderCategoryManager();
    renderCategoryTabs();
    renderCategoryOptions();
    showToast(`Kategori ${emoji} "${label}" ditambahkan.`);
    return category;
  }

  function updateCategoryEmoji(id, emoji) {
    const category = state.categories.find((entry) => entry.id === id);
    if (!category) return;
    const next = normalizeEmoji(emoji) || guessCategoryEmoji(category.label);
    category.emoji = next;
    save(STORAGE_KEYS.categories, state.categories);
    renderCategoryManager();
    renderCategoryTabs();
    renderCategoryOptions();
    renderProducts();
  }

  function renameCategory(id, label) {
    const category = state.categories.find((entry) => entry.id === id);
    if (!category) return;
    const trimmed = String(label || '').trim().slice(0, 24);
    if (!trimmed || trimmed.toLowerCase() === category.label.toLowerCase()) { renderCategoryManager(); return; }
    category.label = trimmed;
    save(STORAGE_KEYS.categories, state.categories);
    renderCategoryManager();
    renderCategoryTabs();
    renderCategoryOptions();
    renderMenuTable();
    renderProducts();
    showToast(`Kategori diganti menjadi "${trimmed}".`);
  }

  function deleteCategory(id) {
    const category = state.categories.find((entry) => entry.id === id);
    if (!category) return;
    const used = state.products.filter((product) => product.category === id).length;
    if (used > 0) { showToast(`Kategori "${category.label}" dipakai ${formatNumber(used)} menu — pindahkan dulu sebelum menghapus.`); return; }
    state.categories = state.categories.filter((entry) => entry.id !== id);
    if (state.category === id) state.category = 'semua';
    save(STORAGE_KEYS.categories, state.categories);
    renderCategoryManager();
    renderCategoryTabs();
    renderCategoryOptions();
    renderMenuTable();
    renderProducts();
    showToast(`Kategori "${category.label}" dihapus.`);
  }

  function handleCategoryAdd(event) {
    event.preventDefault();
    addCategory();
  }
  function formatTime(value) {
    const date = safeDate(value);
    return date ? new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit' }).format(date) : '—';
  }
  function formatDateTime(value) {
    const date = safeDate(value);
    return date ? new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(date) : '—';
  }
  function formatShortDate(value) { return new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(`${value}T00:00:00`)); }
  function uid(prefix) { return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`; }
  function escapeHtml(value) { return String(value ?? '').replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#039;', '"': '&quot;' }[character])); }
  function escapeAttr(value) { return escapeHtml(value).replace(/`/g, '&#096;'); }
  function downloadFile(filename, content, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 500);
  }
  /* ---------- Export Excel (.xlsx) ----------
     Membuat berkas .xlsx asli (ZIP store + sheet XML inlineStr) supaya
     terbuka tanpa peringatan format. Header: nama warung, judul laporan,
     periode, waktu unduh; lalu ringkasan, rekap harian (per hari), rekap
     bulanan (hanya bila rentang lintas bulan), dan rincian transaksi —
     semuanya ditutup baris TOTAL tebal. */
  function xlsxEscape(value) {
    return String(value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }

  function buildReportXlsx(range, orders, title, kindLabel) {
    const cols = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    const refAt = (row, col) => `${cols[col - 1]}${row}`;
    const cells = [];   // { ref, s, v, n }
    const merges = [];
    const pushCell = (row, col, style, value, numeric = false) => cells.push({ ref: refAt(row, col), s: style, v: value, n: numeric });
    const pushMerged = (row, colFrom, colTo) => { if (colTo > colFrom) merges.push(`${refAt(row, colFrom)}:${refAt(row, colTo)}`); };
    const itemCountOf = (order) => orderItems(order).reduce((sum, item) => sum + Number(item.qty || 0), 0);
    const groupBy = (keyFn) => {
      const map = new Map();
      orders.forEach((order) => {
        const key = keyFn(order);
        const cur = map.get(key) || { count: 0, items: 0, total: 0 };
        cur.count += 1;
        cur.items += itemCountOf(order);
        cur.total += Number(order.total || 0);
        map.set(key, cur);
      });
      return [...map.keys()].sort();
    };

    const revenue = orders.reduce((sum, order) => sum + Number(order.total || 0), 0);
    const itemCount = orders.reduce((sum, order) => sum + itemCountOf(order), 0);
    const daily = new Map();

    let row = 1;
    // 1) Header
    pushCell(row, 1, 1, state.settings.businessName || 'Mie Pangsit Jakarta'); pushMerged(row, 1, 7); row++;
    pushCell(row, 1, 2, title || 'LAPORAN PENJUALAN'); pushMerged(row, 1, 7); row++;
    pushCell(row, 1, 0, `Jenis: ${kindLabel || 'Rentang'} (${range.from === range.to ? '1 hari' : 'beberapa hari'})`); pushMerged(row, 1, 7); row++;
    pushCell(row, 1, 0, `Periode: ${range.from} s.d. ${range.to}`); pushMerged(row, 1, 7); row++;
    pushCell(row, 1, 0, `Diunduh: ${new Date().toLocaleString('id-ID')}`); pushMerged(row, 1, 7); row++;
    row++;

    // 2) Ringkasan
    pushCell(row, 1, 2, 'RINGKASAN'); pushMerged(row, 1, 7); row++;
    pushCell(row, 1, 2, 'Total omzet'); pushCell(row, 2, 3, Math.round(revenue), true); pushMerged(row, 2, 3);
    pushCell(row, 4, 2, 'Transaksi'); pushCell(row, 5, 3, orders.length, true); pushMerged(row, 5, 7); row++;
    pushCell(row, 1, 2, 'Item terjual'); pushCell(row, 2, 3, itemCount, true); pushMerged(row, 2, 3);
    pushCell(row, 4, 2, 'Rata-rata / transaksi'); pushCell(row, 5, 3, Math.round(orders.length ? revenue / orders.length : 0), true); pushMerged(row, 5, 7); row++;
    row++;

    const headerRow = (labels) => {
      labels.forEach((label, index) => pushCell(row, index + 1, 7, label));
      row++;
    };

    const emitGroupRows = (keys, map, labelFn) => {
      keys.forEach((key, index) => {
        const cur = map.get(key);
        pushCell(row, 1, 5, index + 1, true);
        pushCell(row, 2, 5, labelFn(key));
        pushCell(row, 3, 6, cur.count, true);
        pushCell(row, 4, 6, cur.items, true);
        pushCell(row, 5, 6, Math.round(cur.total), true);
        row++;
      });
      pushCell(row, 1, 7, 'TOTAL'); pushMerged(row, 1, 2);
      pushCell(row, 3, 8, orders.length, true);
      pushCell(row, 4, 8, itemCount, true);
      pushCell(row, 5, 8, Math.round(revenue), true);
      row++;
      row++;
    };

    // 3) Rekap harian
    pushCell(row, 1, 2, 'REKAP HARIAN'); pushMerged(row, 1, 7); row++;
    headerRow(['No', 'Tanggal', 'Transaksi', 'Item', 'Omzet']);
    orders.forEach((order) => {
      const day = orderDate(order);
      const cur = daily.get(day) || { count: 0, items: 0, total: 0 };
      cur.count += 1;
      cur.items += itemCountOf(order);
      cur.total += Number(order.total || 0);
      daily.set(day, cur);
    });
    emitGroupRows([...daily.keys()].sort(), daily, (day) => day);
    row--;

    // 4) Rekap bulanan (hanya kalau rentang lintas bulan)
    const months = new Set(orders.map((order) => orderDate(order).slice(0, 7)));
    if (months.size > 1) {
      pushCell(row, 1, 2, 'REKAP BULANAN'); pushMerged(row, 1, 7); row++;
      headerRow(['No', 'Bulan', 'Transaksi', 'Item', 'Omzet']);
      const monthly = new Map();
      orders.forEach((order) => {
        const key = orderDate(order).slice(0, 7);
        const cur = monthly.get(key) || { count: 0, items: 0, total: 0 };
        cur.count += 1;
        cur.items += itemCountOf(order);
        cur.total += Number(order.total || 0);
        monthly.set(key, cur);
      });
      emitGroupRows([...monthly.keys()].sort(), monthly, (key) => new Date(`${key}-01T00:00:00`).toLocaleDateString('id-ID', { month: 'long', year: 'numeric' }));
    }

    // 5) Rincian transaksi
    pushCell(row, 1, 2, 'RINCIAN TRANSAKSI'); pushMerged(row, 1, 7); row++;
    headerRow(['No', 'Tanggal', 'Jam', 'No. Transaksi', 'Pesanan', 'Pembayaran', 'Total']);
    orders.forEach((order, index) => {
      const items = orderItems(order).map((item) => `${item.qty}x ${item.name}`).join(', ');
      pushCell(row, 1, 5, index + 1, true);
      pushCell(row, 2, 5, orderDate(order));
      pushCell(row, 3, 5, formatTime(order.createdAt));
      pushCell(row, 4, 5, order.id);
      pushCell(row, 5, 5, items);
      pushCell(row, 6, 5, paymentLabel(order.payment));
      pushCell(row, 7, 6, Math.round(Number(order.total || 0)), true);
      row++;
    });
    pushCell(row, 1, 7, 'TOTAL'); pushMerged(row, 1, 6);
    pushCell(row, 7, 8, Math.round(revenue), true);

    // Susun XML worksheet
    const byRow = new Map();
    cells.forEach((cell) => {
      const r = parseInt(cell.ref.slice(1), 10);
      if (!byRow.has(r)) byRow.set(r, []);
      byRow.get(r).push(cell);
    });
    const rowsXml = [...byRow.keys()].sort((a, b) => a - b).map((r) => {
      const inner = byRow.get(r).sort((a, b) => (a.ref < b.ref ? -1 : 1)).map((cell) => (
        cell.n
          ? `<c r="${cell.ref}" s="${cell.s}"><v>${cell.v}</v></c>`
          : `<c r="${cell.ref}" s="${cell.s}" t="inlineStr"><is><t>${xlsxEscape(cell.v)}</t></is></c>`
      )).join('');
      return `<row r="${r}">${inner}</row>`;
    }).join('');
    const colsXml = [6, 12, 10, 20, 42, 15, 13].map((width, index) => `<col min="${index + 1}" max="${index + 1}" width="${width}" customWidth="1"/>`).join('');
    const mergesXml = merges.length ? `<mergeCells count="${merges.length}">${merges.map((m) => `<mergeCell ref="${m}"/>`).join('')}</mergeCells>` : '';
    const sheetXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>${colsXml}</cols><sheetData>${rowsXml}</sheetData>${mergesXml}</worksheet>`;

    const contentTypesXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`;
    const relsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`;
    const workbookXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Laporan" sheetId="1" r:id="rId1"/></sheets></workbook>`;
    const workbookRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`;
    const stylesXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="14"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FF9AA5AD"/></left><right style="thin"><color rgb="FF9AA5AD"/></right><top style="thin"><color rgb="FF9AA5AD"/></top><bottom style="thin"><color rgb="FF9AA5AD"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="9"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="2" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/><xf numFmtId="2" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/><xf numFmtId="2" fontId="2" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;

    const encoder = new TextEncoder();
    return buildXlsxZip([
      { name: '[Content_Types].xml', data: encoder.encode(contentTypesXml) },
      { name: '_rels/.rels', data: encoder.encode(relsXml) },
      { name: 'xl/workbook.xml', data: encoder.encode(workbookXml) },
      { name: 'xl/_rels/workbook.xml.rels', data: encoder.encode(workbookRelsXml) },
      { name: 'xl/styles.xml', data: encoder.encode(stylesXml) },
      { name: 'xl/worksheets/sheet1.xml', data: encoder.encode(sheetXml) }
    ]);
  }

  function buildXlsxZip(files) {
    const encoder = new TextEncoder();
    const pieces = [];
    const centralPieces = [];
    let offset = 0;
    files.forEach((file) => {
      const nameBytes = encoder.encode(file.name);
      const crc = crc32bytes(file.data);
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034B50, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, 0, true);
      local.setUint16(8, 0, true);
      local.setUint16(10, 0, true);
      local.setUint16(12, 0x21, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, file.data.length, true);
      local.setUint32(22, file.data.length, true);
      local.setUint16(26, nameBytes.length, true);
      local.setUint16(28, 0, true);
      pieces.push(new Uint8Array(local.buffer), nameBytes, file.data);
      const cd = new DataView(new ArrayBuffer(46));
      cd.setUint32(0, 0x02014B50, true);
      cd.setUint16(4, 20, true);
      cd.setUint16(6, 20, true);
      cd.setUint16(8, 0, true);
      cd.setUint16(10, 0, true);
      cd.setUint16(12, 0x21, true);
      cd.setUint32(16, crc, true);
      cd.setUint32(20, file.data.length, true);
      cd.setUint32(24, file.data.length, true);
      cd.setUint16(28, nameBytes.length, true);
      cd.setUint16(30, 0, true);
      cd.setUint16(32, 0, true);
      cd.setUint16(34, 0, true);
      cd.setUint16(36, 0, true);
      cd.setUint32(38, 0, true);
      cd.setUint32(42, offset, true);
      centralPieces.push(new Uint8Array(cd.buffer), nameBytes);
      offset += 30 + nameBytes.length + file.data.length;
    });
    const cdOffset = pieces.reduce((sum, piece) => sum + piece.length, 0);
    const cdBytes = concatBytes(centralPieces);
    const eocd = new DataView(new ArrayBuffer(22));
    eocd.setUint32(0, 0x06054B50, true);
    eocd.setUint16(4, 0, true);
    eocd.setUint16(6, 0, true);
    eocd.setUint16(8, files.length, true);
    eocd.setUint16(10, files.length, true);
    eocd.setUint32(12, cdBytes.length, true);
    eocd.setUint32(16, cdOffset, true);
    eocd.setUint16(20, 0, true);
    return concatBytes([...pieces, cdBytes, new Uint8Array(eocd.buffer)]);
  }

  let crcTable = null;
  function crc32bytes(bytes) {
    if (!crcTable) {
      crcTable = [];
      for (let n = 0; n < 256; n += 1) {
        let c = n;
        for (let k = 0; k < 8; k += 1) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        crcTable[n] = c >>> 0;
      }
    }
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i += 1) crc = crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function concatBytes(arrays) {
    const total = arrays.reduce((sum, arr) => sum + arr.length, 0);
    const result = new Uint8Array(total);
    let at = 0;
    arrays.forEach((arr) => { result.set(arr, at); at += arr.length; });
    return result;
  }

  function bytesToBase64(bytes) {
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
  }

  function exportShareNative(filename, bytes) {
    const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    const plugin = nativePlugin('DocumentShare');
    if (!plugin) {
      showToast('Komponen file belum siap di perangkat ini (plugin DocumentShare tidak ditemukan). Beri tahu teknisi.', 6000);
      return;
    }
    const b64 = bytesToBase64(bytes);
    if (typeof plugin.saveToDownloads === 'function') {
      plugin.saveToDownloads({ fileName: filename, base64: b64, mime })
        .then((result) => {
          const savedAs = result && result.savedAs ? result.savedAs : '';
          const size = result && result.size ? Number(result.size) : 0;
          showToast(savedAs
            ? `Tersimpan di folder Download: ${savedAs}${size ? ` (${size.toLocaleString('id-ID')} byte)` : ''}`
            : 'Pilih tujuan di dialog yang terbuka untuk menyimpan laporan.', 6000);
        })
        .catch((error) => {
          // Cadangan: dialog "Simpan / kirim" (Drive, WhatsApp, dll.)
          if (typeof plugin.share === 'function') {
            plugin.share({ fileName: filename, base64: b64, mime })
              .catch((shareError) => {
                showToast(`Export Excel gagal (${(shareError && shareError.message) || 'lihat log'}).`, 6000);
              });
          } else {
            showToast(`Export Excel gagal (${(error && error.message) || 'lihat log'}).`, 6000);
          }
        });
    } else if (typeof plugin.share === 'function') {
      plugin.share({ fileName: filename, base64: b64, mime })
        .catch((error) => showToast(`Export Excel gagal (${(error && error.message) || 'lihat log'}).`, 6000));
    } else {
      showToast('Export Excel gagal — modul file tidak tersedia di aplikasi ini.', 6000);
    }
  }
})();
