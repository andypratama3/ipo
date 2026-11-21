import 'package:material_ui/material_ui.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/print_service.dart';
import '../services/qris_service.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showHeading = true});

  /// Saat dibuka lewat route/AppBar atau topbar sidebar, judul halaman sudah
  /// tampil di atas sehingga heading di dalam layar tidak perlu diulang.
  final bool showHeading;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _labels = [
    ('Toko', Icons.storefront_rounded),
    ('Pembayaran', Icons.qr_code_2_rounded),
    ('Printer & struk', Icons.print_rounded),
    ('Server & cadangan', Icons.cloud_sync_rounded),
    ('Pengguna', Icons.people_alt_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _labels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!controller.isOwner) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Khusus pemilik',
        message: 'Menu dan Pengaturan hanya bisa dibuka oleh akun Pemilik.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.showHeading ? 8 : 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showHeading) ...[
                const PageHeading(
                  kicker: 'Sistem',
                  title: 'Pengaturan',
                  subtitle: 'Dibagi jadi beberapa kelompok supaya mudah dicari.',
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 42,
                child: AnimatedBuilder(
                  animation: _tabs,
                  builder: (context, _) => ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _labels.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => _SettingsTabPill(
                      label: _labels[index].$1,
                      icon: _labels[index].$2,
                      active: _tabs.index == index,
                      onTap: () => _tabs.animateTo(index),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _StoreTab(),
              _PaymentTab(),
              _PrinterTab(),
              _ServerTab(),
              _UsersTab(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pil tab pengaturan, meniru `.settings-tab` di `pos.css`.
class _SettingsTabPill extends StatelessWidget {
  const _SettingsTabPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.62);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [PosColors.sky, PosColors.skyDark],
                  )
                : null,
            color: active ? null : theme.cardTheme.color,
            border: Border.all(
              color: active ? Colors.transparent : theme.dividerColor,
            ),
            boxShadow: [
              BoxShadow(
                color: active
                    ? PosColors.sky.withValues(alpha: 0.28)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: active ? 18 : 5,
                offset: active ? const Offset(0, 7) : const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? Colors.white : muted),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ==========================================================================
   TOKO
   ========================================================================== */

class _StoreTab extends StatefulWidget {
  const _StoreTab();

  @override
  State<_StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<_StoreTab> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppController>().settings;
    _name = TextEditingController(text: settings.businessName);
    _address = TextEditingController(text: settings.businessAddress);
    _phone = TextEditingController(text: settings.businessPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SectionCard(
          kicker: 'Profil usaha',
          title: 'Identitas warung',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Nama usaha',
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Alamat',
                hint: 'Tampil di struk. Boleh lebih dari satu baris.',
                child: TextField(
                  controller: _address,
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Nomor telepon',
                hint: 'Tampil di struk sebagai "Telp/WA: …". Kosongkan bila tidak ingin ditampilkan.',
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'mis. 0812-3456-7890'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => controller.saveBusiness(
                  name: _name.text,
                  address: _address.text,
                  phone: _phone.text,
                ),
                icon: const Icon(Icons.save_rounded, size: 19),
                label: const Text('Simpan identitas'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          kicker: 'Akun aktif',
          title: 'Shift saat ini',
          child: Column(
            children: [
              InfoRow(
                label: 'Nama',
                value: controller.user?.name ?? '-',
              ),
              InfoRow(
                label: 'Peran',
                value: controller.user?.role ?? '-',
              ),
              InfoRow(
                label: 'Masuk',
                value: controller.user == null
                    ? '-'
                    : formatDateTime(
                        DateTime.fromMillisecondsSinceEpoch(controller.user!.loginAt)
                            .toIso8601String(),
                      ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Keluar dari aplikasi?',
                      message:
                          'Keranjang yang sedang berjalan tetap tersimpan untuk kasir berikutnya.',
                      confirmLabel: 'Keluar',
                    );
                    if (ok) await controller.logout();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Keluar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ==========================================================================
   PEMBAYARAN / QRIS
   ========================================================================== */

class _PaymentTab extends StatefulWidget {
  const _PaymentTab();

  @override
  State<_PaymentTab> createState() => _PaymentTabState();
}

class _PaymentTabState extends State<_PaymentTab> {
  late final TextEditingController _payload;
  String? _status;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _payload = TextEditingController(
      text: context.read<AppController>().settings.qrisStaticPayload,
    );
  }

  @override
  void dispose() {
    _payload.dispose();
    super.dispose();
  }

  String get _merchant {
    final text = _payload.text.trim();
    if (text.isEmpty) return '';
    try {
      return QrisService.parse(text).merchantName;
    } catch (_) {
      return '';
    }
  }

  Future<void> _readImage() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _status = null;
    });
    final picker = ImagePicker();
    try {
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final scanner = MobileScannerController(autoStart: false);
      try {
        final capture = await scanner.analyzeImage(file.path);
        final raw = capture?.barcodes
            .map((barcode) => barcode.rawValue)
            .whereType<String>()
            .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
        if (raw == null || raw.trim().isEmpty) {
          setState(() => _status = 'Tidak ada kode QR yang terbaca di foto itu.');
          return;
        }
        _payload.text = raw.trim();
        final validation = QrisService.validate(raw.trim());
        setState(() {
          _status = validation.valid
              ? 'QRIS terbaca. Periksa nama merchant lalu simpan.'
              : 'QR terbaca, tetapi bukan QRIS valid: ${validation.errors.join(' · ')}';
        });
      } finally {
        await scanner.dispose();
      }
    } catch (error) {
      setState(() => _status = 'Gagal membaca foto: $error');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    final controller = context.read<AppController>();
    final error = await controller.saveQris(_payload.text);
    if (!mounted) return;
    if (error != null) {
      setState(() => _status = error);
    } else {
      setState(() => _status = 'QRIS statis tersimpan.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final configured = controller.qrisPayload.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SectionCard(
          kicker: 'Pembayaran QRIS',
          title: 'QRIS dinamis',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: PosColors.sky.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded,
                          color: PosColors.sky),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'QRIS dinamis',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            configured
                                ? 'Siap membuat QR bernominal'
                                : 'Belum diatur',
                            style: TextStyle(
                              fontSize: 11.5,
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: configured ? 'Aktif' : 'Perlu QRIS',
                      tone: configured ? PillTone.success : PillTone.warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _reading ? null : _readImage,
                icon: _reading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_rounded, size: 18),
                label: Text(_reading ? 'Membaca foto…' : 'Baca dari foto QRIS'),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih foto atau screenshot QRIS — kolom di bawah terisi otomatis. '
                'Foto diproses di perangkat, tidak diunggah ke mana pun.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: 'String QRIS statis',
                child: TextField(
                  controller: _payload,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '00020101021126…6304XXXX',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LabeledField(
                label: 'Nama merchant (otomatis)',
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    _merchant.isEmpty ? 'Terisi setelah string QRIS dibaca' : _merchant,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: _merchant.isEmpty
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: toneOf(context, PillTone.info).background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _status!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: toneOf(context, PillTone.info).foreground,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Tempel string QRIS statis warung (bisa dibaca dari QR cetak di meja/kasir). '
                'Setelah disimpan, kasir bisa menampilkan QRIS dinamis bernominal sesuai '
                'total transaksi — dibuat offline di perangkat, tanpa server atau gateway.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded, size: 19),
                      label: const Text('Simpan QRIS'),
                    ),
                  ),
                  if (configured) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        _payload.clear();
                        await controller.saveQris('');
                        if (mounted) setState(() => _status = 'QRIS dikosongkan.');
                      },
                      child: const Text('Kosongkan'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ==========================================================================
   PRINTER & STRUK
   ========================================================================== */

class _PrinterTab extends StatefulWidget {
  const _PrinterTab();

  @override
  State<_PrinterTab> createState() => _PrinterTabState();
}

class _PrinterTabState extends State<_PrinterTab> {
  late final TextEditingController _footer;
  late final TextEditingController _rejection;
  late String _model;
  late String _paper;
  List<BluetoothDevice> _devices = [];
  bool _loadingDevices = false;
  String? _printerStatus;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppController>().settings;
    _footer = TextEditingController(text: settings.receiptFooter);
    _rejection = TextEditingController(text: settings.onlineRejectionMessage);
    _model = settings.printerModel;
    _paper = settings.receiptPaperSize;
  }

  @override
  void dispose() {
    _footer.dispose();
    _rejection.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    if (_loadingDevices) return;
    final controller = context.read<AppController>();
    setState(() {
      _loadingDevices = true;
      _printerStatus = null;
    });
    try {
      final status = await Permission.bluetoothConnect.request();
      if (!status.isGranted && !status.isLimited) {
        setState(() => _printerStatus =
            'Izin Bluetooth ditolak. Beri izin lewat Pengaturan Android.');
        return;
      }
      final enabled = await controller.printer.isBluetoothEnabled();
      if (!enabled) {
        final turnedOn = await controller.printer.requestEnableBluetooth();
        if (!turnedOn) {
          setState(() => _printerStatus = 'Bluetooth masih mati.');
          return;
        }
      }
      final devices = await controller.printer.bondedDevices();
      setState(() {
        _devices = devices;
        _printerStatus = devices.isEmpty
            ? 'Belum ada perangkat dipasangkan. Pasangkan printer dari Pengaturan Bluetooth HP.'
            : '${devices.length} perangkat ditemukan.';
      });
    } catch (error) {
      setState(() => _printerStatus = 'Gagal memuat perangkat: $error');
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _testPrint() async {
    final controller = context.read<AppController>();
    final address = controller.settings.printerAddress;
    if (address.isEmpty) {
      setState(() => _printerStatus = 'Pilih perangkat Bluetooth dulu.');
      return;
    }
    setState(() => _printerStatus = 'Mengirim test cetak…');
    try {
      final settings = controller.settings;
      await controller.printer.printEscPos(
        address: address,
        paperSize: settings.receiptPaperSize,
        lines: [
          ReceiptLine(
            settings.businessName,
            bold: true,
            big: true,
            align: ReceiptAlign.center,
          ),
          const ReceiptLine('TEST CETAK', align: ReceiptAlign.center),
          const ReceiptLine.divider(),
          const ReceiptLine('Printer siap dipakai.', align: ReceiptAlign.center),
          const ReceiptLine('Mie Pangsit Jakarta POS', align: ReceiptAlign.center),
        ],
      );
      setState(() => _printerStatus = 'Test cetak terkirim. Cek kertas printer.');
    } catch (error) {
      setState(() => _printerStatus = 'Test cetak gagal: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final settings = controller.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SectionCard(
          kicker: 'Pencetakan',
          title: 'Printer Bluetooth',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Model printer',
                child: DropdownButtonFormField<String>(
                  initialValue: _model,
                  items: const [
                    DropdownMenuItem(value: 'x58bt', child: Text('iware X58BT II')),
                    DropdownMenuItem(value: 'mp58', child: Text('MP58')),
                    DropdownMenuItem(
                      value: 'generic',
                      child: Text('Printer 58 mm umum'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _model = value);
                    await controller.setPrinter(
                      model: value,
                      address: settings.printerAddress,
                      name: settings.printerDeviceName,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Perangkat Bluetooth',
                child: DropdownButtonFormField<String>(
                  initialValue: settings.printerAddress.isEmpty
                      ? null
                      : settings.printerAddress,
                  isExpanded: true,
                  items: [
                    if (settings.printerAddress.isNotEmpty &&
                        !_devices.any((device) => device.address == settings.printerAddress))
                      DropdownMenuItem(
                        value: settings.printerAddress,
                        child: Text(
                          settings.printerDeviceName.isEmpty
                              ? settings.printerAddress
                              : '${settings.printerDeviceName} (tersimpan)',
                        ),
                      ),
                    for (final device in _devices)
                      DropdownMenuItem(
                        value: device.address,
                        child: Text(
                          device.name ?? device.address,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    final device = _devices
                        .where((entry) => entry.address == value)
                        .firstOrNull;
                    await controller.setPrinter(
                      model: _model,
                      address: value,
                      name: device?.name ?? settings.printerDeviceName,
                    );
                    setState(() {});
                  },
                  hint: const Text('— pilih perangkat yang sudah dipasangkan —'),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await FlutterBluetoothSerial.instance.openSettings();
                      } catch (_) {
                        setState(() => _printerStatus =
                            'Buka Pengaturan Bluetooth dari HP secara manual.');
                      }
                    },
                    icon: const Icon(Icons.bluetooth_rounded, size: 18),
                    label: const Text('Bluetooth HP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadingDevices ? null : _loadDevices,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Muat ulang'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _testPrint,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Test cetak'),
                  ),
                ],
              ),
              if (_printerStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _printerStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '1) Nyalakan printer dan pasangkan dari Pengaturan Bluetooth HP '
                '(kode 0000 atau 1234). 2) Tekan "Muat ulang" lalu pilih printer. '
                '3) Tekan "Test cetak" untuk memastikan.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          kicker: 'Kertas',
          title: 'Ukuran kertas struk',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _paper,
                items: const [
                  DropdownMenuItem(value: '58mm', child: Text('58 mm (thermal kecil)')),
                  DropdownMenuItem(value: '80mm', child: Text('80 mm (thermal lebar)')),
                  DropdownMenuItem(value: 'A4', child: Text('A4 (PDF)')),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => _paper = value);
                  await controller.setReceiptPaperSize(value);
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Dipakai untuk printer Bluetooth dan PDF struk.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          kicker: 'Struk',
          title: 'Tulisan di struk',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Tulisan bawah struk',
                hint: 'Tiap baris = ganti baris. Kosongkan untuk tulisan bawaan.',
                child: TextField(
                  controller: _footer,
                  maxLines: 3,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: 'mis. Terima kasih sudah makan di tempat!',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              LabeledField(
                label: 'Tulisan penolakan pesanan online',
                hint: 'Ditampilkan sebagai alasan awal saat menolak pesanan.',
                child: TextField(
                  controller: _rejection,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: 'Mohon maaf stok habis',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => controller.saveReceiptFooter(
                  _footer.text,
                  _rejection.text,
                ),
                icon: const Icon(Icons.save_rounded, size: 19),
                label: const Text('Simpan pengaturan tulisan'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ==========================================================================
   SERVER & CADANGAN
   ========================================================================== */

class _ServerTab extends StatefulWidget {
  const _ServerTab();

  @override
  State<_ServerTab> createState() => _ServerTabState();
}

class _ServerTabState extends State<_ServerTab> {
  late final TextEditingController _apiBase;

  @override
  void initState() {
    super.initState();
    _apiBase = TextEditingController(text: context.read<AppController>().apiBase);
  }

  @override
  void dispose() {
    _apiBase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final status = controller.syncStatus;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SectionCard(
          kicker: 'Sinkronisasi',
          title: 'Server & sinkronisasi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: PosColors.sky.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cloud_sync_rounded,
                          color: PosColors.sky),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sinkronisasi IPOS',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            status?.label ?? 'Mode lokal aktif',
                            style: TextStyle(
                              fontSize: 11.5,
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: status?.label ?? 'Lokal',
                      tone: !controller.isConfigured
                          ? PillTone.neutral
                          : (status?.error.isNotEmpty ?? false)
                              ? PillTone.danger
                              : (status?.queued ?? 0) > 0
                                  ? PillTone.warning
                                  : PillTone.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Alamat server (API)',
                hint: 'Kosongkan untuk mode lokal (tanpa sinkronisasi). Setelah diisi, '
                    'keluar lalu masuk lagi supaya masuk lewat server.',
                child: TextField(
                  controller: _apiBase,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'https://ipos-api.contoh.com',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sinkronisasi aktif'),
                subtitle: const Text(
                  'Perubahan dikirim otomatis ke server saat ada internet.',
                ),
                value: controller.syncEnabled,
                onChanged: controller.setSyncEnabled,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => controller.saveApiBase(_apiBase.text),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Simpan alamat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.manualSync,
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Sinkron sekarang'),
                    ),
                  ),
                ],
              ),
              if (status != null && status.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    status.error,
                    style: const TextStyle(fontSize: 11.5, color: PosColors.red),
                  ),
                ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${status.queued} perubahan menunggu · '
                    'perangkat ${status.deviceId}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          kicker: 'Data lokal',
          title: 'Cadangkan data',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'POS ini menyimpan data di perangkat ini. Aplikasi hanya menyimpan '
                'satu cadangan otomatis terbaru (cadangan lama diganti) supaya '
                'penyimpanan tidak penuh. Salinan di server mengikuti sinkronisasi; '
                'tetap unduh file backup ke Google Drive minimal seminggu sekali.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.exportBackup,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Unduh backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.importBackup,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Impor backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.takeSnapshotNow,
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Cadangan sekarang'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Bersihkan riwayat?',
                        message:
                            'Semua transaksi, pesanan bayar nanti, dan pesanan online '
                            'dihapus dari perangkat ini. Menu dan pengaturan tetap. '
                            'Stok TIDAK dikembalikan.',
                        confirmLabel: 'Bersihkan',
                        danger: true,
                      );
                      if (ok) await controller.clearHistory();
                    },
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Bersihkan riwayat'),
                    style: TextButton.styleFrom(foregroundColor: PosColors.red),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                controller.lastExport.isEmpty
                    ? 'Belum pernah mengunduh file backup. Data di perangkat hilang '
                        'kalau aplikasi di-uninstall.'
                    : 'Backup terakhir diunduh: ${formatDateTime(controller.lastExport)}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: controller.lastExport.isEmpty
                      ? PosColors.orange
                      : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              if (controller.snapshots.isNotEmpty) ...[
                const SizedBox(height: 12),
                const DashedDivider(),
                for (final snapshot in controller.snapshots)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.reason.isEmpty ? 'Cadangan lokal' : snapshot.reason,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${formatDateTime(snapshot.at)} · '
                          '${formatNumber(snapshot.ordersCount)} transaksi',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: 'Kembalikan cadangan?',
                                  message:
                                      'Data saat ini diganti dengan isi cadangan. '
                                      'Cadangan terbaru dibuat otomatis sebelum pemulihan.',
                                  confirmLabel: 'Kembalikan',
                                );
                                if (ok) await controller.restoreSnapshot(snapshot.id);
                              },
                              child: const Text('Kembalikan'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: 'Hapus cadangan?',
                                  message: 'Titik pemulihan ini dihapus dari perangkat.',
                                  confirmLabel: 'Hapus',
                                  danger: true,
                                );
                                if (ok) await controller.deleteSnapshot(snapshot.id);
                              },
                              style: TextButton.styleFrom(foregroundColor: PosColors.red),
                              child: const Text('Hapus'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/* ==========================================================================
   PENGGUNA
   ========================================================================== */

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  String _role = 'Kasir';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AppController>();
      if (controller.accountsFromServer && controller.serverUsers == null) {
        controller.loadServerUsers();
      }
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    final controller = context.read<AppController>();
    setState(() => _busy = true);
    final error = await controller.createUser(
      usernameRaw: _username.text,
      nameRaw: _name.text,
      role: _role,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      _username.clear();
      _name.clear();
      _password.clear();
      setState(() => _role = 'Kasir');
    } else {
      showAppSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final serverMode = controller.accountsFromServer;
    final accounts = serverMode
        ? (controller.serverUsers ?? const <ServerUser>[])
            .map((user) => _AccountView(
                  serverId: user.id,
                  username: user.username,
                  name: user.name,
                  role: user.role,
                  active: user.active,
                ))
            .toList()
        : controller.localUsers
            .map((user) => _AccountView(
                  username: user.username,
                  name: user.name,
                  role: user.role,
                  active: user.active,
                ))
            .toList();
    final loadFailed = serverMode && controller.serverUsers == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SectionCard(
          kicker: 'Akun',
          title: serverMode ? 'Daftar pengguna server' : 'Daftar pengguna lokal',
          trailing: serverMode
              ? TextButton.icon(
                  onPressed: () => controller.loadServerUsers(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Muat ulang'),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                serverMode
                    ? 'Akun tersimpan di server. Tekan "Ubah" untuk mengganti '
                        'nama atau sandi.'
                    : 'Mode lokal: akun tersimpan di perangkat ini. Sandi '
                        'bawaan 1234 — segera ganti lewat "Ubah".',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              if (serverMode && controller.userListStatus.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  controller.userListStatus,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: loadFailed
                        ? PosColors.red
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (accounts.isEmpty)
                Text(
                  loadFailed
                      ? 'Daftar akun belum bisa dimuat dari server. Periksa '
                          'alamat server dan sambungan internet, lalu tekan '
                          '"Muat ulang".'
                      : serverMode
                          ? 'Belum ada akun di server. Tambahkan lewat '
                              'formulir "Tambah pengguna".'
                          : 'Belum ada akun.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                )
              else
                for (final account in accounts)
                  _accountRow(context, controller, theme, account),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          kicker: 'Akun baru',
          title: 'Tambah pengguna',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Nama pengguna',
                hint: 'Huruf kecil, angka, titik, garis bawah, strip (3-60 karakter).',
                child: TextField(
                  controller: _username,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'mis. kasir2'),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Nama tampilan',
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'mis. Kasir 2'),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Peran',
                child: DropdownButtonFormField<String>(
                  initialValue: _role,
                  items: const [
                    DropdownMenuItem(value: 'Kasir', child: Text('Kasir')),
                    DropdownMenuItem(value: 'Pemilik', child: Text('Pemilik')),
                  ],
                  onChanged: (value) => setState(() => _role = value ?? 'Kasir'),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Sandi awal',
                hint: 'Minimal 6 karakter.',
                child: TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'min. 6 karakter'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 19),
                label: Text(_busy ? 'Menyimpan…' : 'Tambah pengguna'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountRow(
    BuildContext context,
    AppController controller,
    ThemeData theme,
    _AccountView account,
  ) {
    final isSelf = controller.user?.username == account.username;
    final label = account.name.isEmpty ? account.username : account.name;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
                theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      const StatusPill(label: 'Anda', tone: PillTone.info),
                    ],
                  ],
                ),
                Text(
                  '${account.username} · ${account.role}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          StatusPill(
            label: account.active ? 'Aktif' : 'Nonaktif',
            tone: account.active ? PillTone.success : PillTone.neutral,
          ),
          PopupMenuButton<String>(
            tooltip: 'Aksi akun',
            onSelected: (value) async {
              if (value == 'edit') {
                await _editAccount(context, controller, account);
              } else if (value == 'toggle') {
                await _toggleAccount(context, controller, account);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 19),
                  title: Text('Ubah akun'),
                ),
              ),
              if (!isSelf)
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      account.active
                          ? Icons.person_off_outlined
                          : Icons.person_outline_rounded,
                      size: 19,
                    ),
                    title: Text(
                      account.active ? 'Nonaktifkan' : 'Aktifkan',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editAccount(
    BuildContext context,
    AppController controller,
    _AccountView account,
  ) async {
    if (account.serverId == null) {
      final local = controller.findLocalUser(account.username);
      if (local == null) {
        showAppSnack(context, 'Akun tidak ditemukan.');
        return;
      }
      await _editUser(context, controller, local);
      return;
    }
    await _editServerUser(context, controller, account);
  }

  Future<void> _toggleAccount(
    BuildContext context,
    AppController controller,
    _AccountView account,
  ) async {
    String? error;
    if (account.serverId == null) {
      error = await controller.toggleLocalUser(account.username);
    } else {
      ServerUser? entry;
      for (final item in controller.serverUsers ?? const <ServerUser>[]) {
        if (item.id == account.serverId) {
          entry = item;
          break;
        }
      }
      error = entry == null
          ? 'Akun tidak ditemukan.'
          : await controller.toggleServerUser(entry);
    }
    if (error != null && context.mounted) showAppSnack(context, error);
  }

  Future<void> _editServerUser(
    BuildContext context,
    AppController controller,
    _AccountView account,
  ) async {
    final name = TextEditingController(text: account.name);
    final password = TextEditingController();
    var role = account.role;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Ubah ${account.username}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama tampilan'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: const [
                    DropdownMenuItem(value: 'Kasir', child: Text('Kasir')),
                    DropdownMenuItem(value: 'Pemilik', child: Text('Pemilik')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Sandi baru (opsional)',
                    hintText: 'Kosongkan bila tidak diganti',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final error = await controller.updateServerUser(
        id: account.serverId!,
        name: name.text,
        role: role,
        password: password.text,
      );
      if (error != null && context.mounted) showAppSnack(context, error);
    }
    name.dispose();
    password.dispose();
  }

  Future<void> _editUser(
    BuildContext context,
    AppController controller,
    LocalUser user,
  ) async {
    final name = TextEditingController(text: user.name);
    final password = TextEditingController();
    var role = user.role;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Ubah ${user.username}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama tampilan'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: const [
                    DropdownMenuItem(value: 'Kasir', child: Text('Kasir')),
                    DropdownMenuItem(value: 'Pemilik', child: Text('Pemilik')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Sandi baru (opsional)',
                    hintText: 'Kosongkan bila tidak diganti',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final error = await controller.updateLocalUser(
        username: user.username,
        name: name.text,
        role: role,
        password: password.text,
      );
      if (error != null && context.mounted) showAppSnack(context, error);
    }
    name.dispose();
    password.dispose();
  }
}

/// Satu baris akun di tab Pengguna, baik dari penyimpanan lokal maupun server.
class _AccountView {
  const _AccountView({
    this.serverId,
    required this.username,
    required this.name,
    required this.role,
    required this.active,
  });

  final String? serverId;
  final String username;
  final String name;
  final String role;
  final bool active;
}
