import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:ipomiepangsit_pos/core/defaults.dart';
import 'package:ipomiepangsit_pos/core/theme.dart';
import 'package:ipomiepangsit_pos/models/models.dart';
import 'package:ipomiepangsit_pos/state/app_controller.dart';
import 'package:ipomiepangsit_pos/ui/app_shell.dart';
import 'package:ipomiepangsit_pos/ui/cashier_screen.dart';
import 'package:ipomiepangsit_pos/ui/dashboard_screen.dart';
import 'package:ipomiepangsit_pos/ui/login_screen.dart';
import 'package:ipomiepangsit_pos/ui/menu_screen.dart';
import 'package:ipomiepangsit_pos/ui/queues_screen.dart';
import 'package:ipomiepangsit_pos/ui/reports_screen.dart';
import 'package:ipomiepangsit_pos/ui/settings_screen.dart';

/// Preview UI khusus TABLET.
///
/// Jalankan:
///   flutter test test/ui_preview_test.dart --update-goldens
/// atau: tool\preview_ui.bat
///
/// Hasil gambar: test/preview/
///
/// Ukuran yang dipakai:
///   - tablet        : 1024 x 768  (tablet 4:3, landscape)
///   - tablet lebar  : 1280 x 800  (tablet 16:10, landscape)

AppController _buildController() {
  final c = AppController();
  c.loading = false;
  c.theme = 'light';
  c.apiBase = 'https://contoh.server';
  c.syncEnabled = true;
  c.now = DateTime(2026, 11, 21, 10, 30);
  c.user = SessionUser(
    username: 'pemilik',
    name: 'Pemilik',
    role: 'Pemilik',
    loginAt: DateTime(2026, 11, 21, 8, 0).millisecondsSinceEpoch,
    loginDay: '2026-11-21',
    loginMinute: 480,
  );
  c.settings = AppSettings(
    businessName: 'Mie Pangsit Jakarta',
    businessAddress: 'Jl. Siradj Salman, Samarinda',
    businessPhone: '0812-3456-7890',
  );
  c.categories = defaultCategories();
  c.products = defaultProducts();
  c.localUsers = defaultLocalUsers();

  final nowIso = DateTime(2026, 11, 21, 10, 0).toUtc().toIso8601String();
  c.orders = [
    Order(
      id: 'MPJ-20261121-00001',
      createdAt: DateTime(2026, 11, 21, 9, 10).toUtc().toIso8601String(),
      items: [
        OrderItem(
          productId: 'pangsit-original',
          name: 'Mie Pangsit Original',
          price: 20000,
          qty: 2,
          total: 40000,
        ),
        OrderItem(
          productId: 'teh-es-panas',
          name: 'Teh Es/Panas',
          price: 6000,
          qty: 2,
          total: 12000,
        ),
      ],
      orderType: 'dine-in',
      tableNumber: '3',
      subtotal: 52000,
      discount: 0,
      total: 52000,
      payment: 'cash',
      paidAmount: 60000,
      changeAmount: 8000,
      status: 'paid',
      cashier: 'Kasir',
    ),
    Order(
      id: 'MPJ-20261121-00002',
      createdAt: DateTime(2026, 11, 21, 9, 45).toUtc().toIso8601String(),
      items: [
        OrderItem(
          productId: 'bakso',
          name: 'Bakso',
          price: 20000,
          qty: 1,
          total: 20000,
        ),
        OrderItem(
          productId: 'jeruk',
          name: 'Jeruk Es/Panas',
          price: 8000,
          qty: 1,
          total: 8000,
        ),
      ],
      orderType: 'takeaway',
      subtotal: 28000,
      discount: 0,
      total: 28000,
      payment: 'qris',
      paidAmount: 28000,
      changeAmount: 0,
      status: 'paid',
      cashier: 'Kasir',
    ),
    Order(
      id: 'MPJ-20261121-00003',
      createdAt: DateTime(2026, 11, 21, 10, 5).toUtc().toIso8601String(),
      items: [
        OrderItem(
          productId: 'paket-komplit',
          name: 'Mie Pangsit Komplit',
          price: 30000,
          qty: 1,
          total: 30000,
        ),
      ],
      orderType: 'dine-in',
      tableNumber: '7',
      subtotal: 30000,
      discount: 0,
      total: 30000,
      payment: 'transfer',
      paidAmount: 30000,
      changeAmount: 0,
      status: 'paid',
      cashier: 'Kasir',
    ),
  ];

  c.pendingOrders = [
    PendingOrder(
      id: 'HOLD-20261121-00001',
      createdAt: nowIso,
      orderType: 'dine-in',
      tableNumber: '5',
      items: [
        OrderItem(
          productId: 'paket-komplit',
          name: 'Mie Pangsit Komplit',
          price: 30000,
          qty: 1,
          total: 30000,
        ),
        OrderItem(
          productId: 'es-kelapa',
          name: 'Es Kelapa',
          price: 15000,
          qty: 1,
          total: 15000,
        ),
      ],
      subtotal: 45000,
      total: 45000,
      cashier: 'Kasir',
      note: 'Tidak pakai daun bawang',
    ),
    PendingOrder(
      id: 'HOLD-20261121-00002',
      createdAt: DateTime(2026, 11, 21, 10, 8).toUtc().toIso8601String(),
      orderType: 'takeaway',
      items: [
        OrderItem(
          productId: 'bakso',
          name: 'Bakso',
          price: 20000,
          qty: 2,
          total: 40000,
        ),
        OrderItem(
          productId: 'jeruk',
          name: 'Jeruk Es/Panas',
          price: 8000,
          qty: 1,
          total: 8000,
        ),
      ],
      subtotal: 48000,
      total: 48000,
      cashier: 'Kasir',
    ),
  ];

  c.onlineOrders = [
    OnlineOrder(
      id: 'ONL-GF-2174',
      source: 'gofood',
      code: 'GF-2174',
      customer: 'Dina',
      note: 'Pedas level 2',
      status: 'baru',
      createdAt: nowIso,
      items: [
        OnlineOrderItem(productId: 'pangsit-original', qty: 2),
        OnlineOrderItem(productId: 'teh-es-panas', qty: 2),
      ],
    ),
    OnlineOrder(
      id: 'ONL-GR-9041',
      source: 'grab',
      code: 'GR-9041',
      customer: 'Rizky',
      status: 'dibuat',
      createdAt: nowIso,
      items: [
        OnlineOrderItem(productId: 'bakso', qty: 1),
        OnlineOrderItem(productId: 'paket-komplit', qty: 1),
      ],
    ),
    OnlineOrder(
      id: 'ONL-SP-5512',
      source: 'shopee',
      code: 'SP-5512',
      customer: 'Maya',
      note: 'Saus sambal dipisah',
      status: 'siap',
      createdAt: nowIso,
      pickupCode: '5512',
      items: [
        OnlineOrderItem(productId: 'mie-kering', qty: 2),
        OnlineOrderItem(productId: 'lemon-tea', qty: 1),
      ],
    ),
    OnlineOrder(
      id: 'ONL-SF-1120',
      source: 'gofood',
      code: 'GF-1120',
      customer: 'Andi',
      status: 'siap',
      createdAt: nowIso,
      pickupCode: '1120',
      items: [
        OnlineOrderItem(productId: 'pangsit-original', qty: 1),
      ],
    ),
  ];

  c.cart = [];
  c.category = 'semua';
  c.search = '';
  c.orderType = 'dine-in';
  c.selectedPayment = 'cash';
  c.cartDiscount = 0;
  c.cartNote = '';
  c.tableNumber = '';
  c.cartTab = 'cart';
  c.onlineStatusFilter = 'baru';
  c.onlinePlatformFilter = 'all';

  return c;
}

/// Controller dengan keranjang terisi, untuk preview kasir versi sibuk.
AppController _buildControllerWithCart() {
  final c = _buildController();
  c.cart = [
    CartItem(
      productId: 'pangsit-original',
      qty: 2,
      name: 'Mie Pangsit Original',
      price: 20000,
      note: 'Pedas level 2',
    ),
    CartItem(
      productId: 'bakso',
      qty: 1,
      name: 'Bakso',
      price: 20000,
    ),
    CartItem(
      productId: 'teh-es-panas',
      qty: 2,
      name: 'Teh Es/Panas',
      price: 6000,
    ),
  ];
  c.tableNumber = '4';
  c.cartDiscount = 5000;
  c.cartNote = 'Satu tanpa daun bawang';
  return c;
}

Widget _app(
  AppController controller,
  Widget home, {
  required Size size,
}) {
  return ChangeNotifierProvider<AppController>.value(
    value: controller,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _previewTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SizedBox(width: size.width, height: size.height, child: home),
      ),
    ),
  );
}

/// Tema sama seperti aplikasi, tapi font-nya dipaksa eksplisit + fallback emoji
/// supaya preview tidak menampilkan kotak-kotak font uji (Ahem).
ThemeData _previewTheme() {
  final base = PosTheme.light();
  const emojiFallback = ['Segoe UI Emoji', 'Noto Color Emoji'];

  TextStyle style(FontWeight weight) => TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: emojiFallback,
        fontWeight: weight,
      );

  WidgetStateProperty<TextStyle> property(FontWeight weight) =>
      WidgetStateProperty.all(style(weight));

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: emojiFallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: emojiFallback,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: property(FontWeight.w700)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: property(FontWeight.w600)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: property(FontWeight.w600)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (base.elevatedButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: property(FontWeight.w700)),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => style(
          states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ).copyWith(fontSize: 10.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: style(FontWeight.w600).copyWith(fontSize: 12),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: style(FontWeight.w700).copyWith(fontSize: 12.5),
      unselectedLabelStyle: style(FontWeight.w600).copyWith(fontSize: 12.5),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: style(FontWeight.w700)
          .copyWith(fontSize: 18, color: base.colorScheme.onSurface),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('preview/$name.png'),
  );
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
    Directory('test/preview').createSync(recursive: true);

    Future<void> loadFamily(String family, List<String> filenames) async {
      final loader = FontLoader(family);
      var added = false;
      for (final name in filenames) {
        final file = File(
          r'D:\web\flutter\bin\cache\artifacts\material_fonts\' + name,
        );
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        added = true;
      }
      if (added) await loader.load();
    }

    // Muat font asli agar preview terbaca, bukan kotak-kotak font uji.
    await loadFamily('Roboto', const [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-italic.ttf',
    ]);
    await loadFamily('MaterialIcons', const ['materialicons-regular.otf']);

    // Emoji fallback (Windows) agar ikon menu/kategori tidak tampil kotak.
    final emojiLoader = FontLoader('Segoe UI Emoji');
    final emojiFile = File(r'C:\Windows\Fonts\seguiemj.ttf');
    if (emojiFile.existsSync()) {
      final bytes = emojiFile.readAsBytesSync();
      emojiLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await emojiLoader.load();
    }
  });

  const tablet = Size(1024, 768);
  const tabletWide = Size(1280, 800);

  /* ---------------------------- TABLET 1024x768 --------------------------- */

  testWidgets('tablet login', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController()..user = null;
    await tester.pumpWidget(_app(c, const LoginScreen(), size: tablet));
    await _capture(tester, 'login_tablet');
  });

  testWidgets('tablet shell beranda', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController();
    await tester.pumpWidget(_app(c, const AppShell(), size: tablet));
    await _capture(tester, 'tablet_shell_dashboard');
  });

  testWidgets('tablet beranda', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController();
    await tester.pumpWidget(
      _app(c, Scaffold(body: DashboardScreen(onNavigate: (_) {})), size: tablet),
    );
    await _capture(tester, 'tablet_dashboard');
  });

  testWidgets('tablet kasir', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController();
    await tester.pumpWidget(
      _app(c, const Scaffold(body: CashierScreen()), size: tablet),
    );
    await _capture(tester, 'tablet_cashier');
  });

  testWidgets('tablet kasir dengan keranjang', (tester) async {
    _setSize(tester, tablet);
    final c = _buildControllerWithCart();
    await tester.pumpWidget(
      _app(c, const Scaffold(body: CashierScreen()), size: tablet),
    );
    await _capture(tester, 'tablet_cashier_cart');
  });

  testWidgets('tablet pesanan bayar nanti', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController()..cartTab = 'pending';
    await tester.pumpWidget(
      _app(
        c,
        Scaffold(body: QueuesScreen(onOpenCashier: () {})),
        size: tablet,
      ),
    );
    await _capture(tester, 'tablet_queues_pending');
  });

  testWidgets('tablet pesanan online', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController()
      ..cartTab = 'online'
      ..onlineStatusFilter = 'siap';
    await tester.pumpWidget(
      _app(
        c,
        Scaffold(body: QueuesScreen(onOpenCashier: () {})),
        size: tablet,
      ),
    );
    await _capture(tester, 'tablet_queues_online');
  });

  testWidgets('tablet menu', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController();
    await tester.pumpWidget(
      _app(c, const Scaffold(body: MenuScreen()), size: tablet),
    );
    await _capture(tester, 'tablet_menu');
  });

  testWidgets('tablet laporan', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController();
    await tester.pumpWidget(
      _app(c, const Scaffold(body: ReportsScreen()), size: tablet),
    );
    await _capture(tester, 'tablet_reports');
  });

  testWidgets('tablet pengaturan', (tester) async {
    _setSize(tester, tablet);
    final c = _buildController();
    await tester.pumpWidget(
      _app(
        c,
        Scaffold(
          appBar: AppBar(title: const Text('Pengaturan')),
          body: const SettingsScreen(showHeading: false),
        ),
        size: tablet,
      ),
    );
    await _capture(tester, 'tablet_settings');
  });

  /* --------------------------- TABLET 1280x800 ---------------------------- */

  testWidgets('tablet lebar beranda', (tester) async {
    _setSize(tester, tabletWide);
    final c = _buildController();
    await tester.pumpWidget(_app(c, const AppShell(), size: tabletWide));
    await _capture(tester, 'wide_shell_dashboard');
  });

  testWidgets('tablet lebar kasir', (tester) async {
    _setSize(tester, tabletWide);
    final c = _buildControllerWithCart();
    await tester.pumpWidget(
      _app(c, const Scaffold(body: CashierScreen()), size: tabletWide),
    );
    await _capture(tester, 'wide_cashier_cart');
  });

  testWidgets('tablet lebar laporan', (tester) async {
    _setSize(tester, tabletWide);
    final c = _buildController();
    await tester.pumpWidget(
      _app(c, const Scaffold(body: ReportsScreen()), size: tabletWide),
    );
    await _capture(tester, 'wide_reports');
  });
}
