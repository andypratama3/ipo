import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/defaults.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

class QueuesScreen extends StatefulWidget {
  const QueuesScreen({super.key, required this.onOpenCashier});

  final VoidCallback onOpenCashier;

  @override
  State<QueuesScreen> createState() => _QueuesScreenState();
}

class _QueuesScreenState extends State<QueuesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final initial = context.read<AppController>().cartTab == 'online' ? 1 : 0;
    _tabs = TabController(length: 2, vsync: this, initialIndex: initial);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      context.read<AppController>().switchCartTab(_tabs.index == 1 ? 'online' : 'pending');
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final pendingCount = controller.pendingOrders.length;
    final onlineActive = controller.onlineOrders.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                kicker: 'Antrean',
                title: 'Pesanan berjalan',
                subtitle: 'Pesanan yang belum dibayar dan pesanan online.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color ?? Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: TabBar(
                  controller: _tabs,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [PosColors.sky, PosColors.skyDark],
                    ),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: PosColors.sky.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor:
                      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  unselectedLabelStyle:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  tabs: [
                    Tab(text: 'Bayar nanti ($pendingCount)'),
                    Tab(text: 'Online ($onlineActive)'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _PendingList(onOpenCashier: widget.onOpenCashier),
              const _OnlineList(),
            ],
          ),
        ),
      ],
    );
  }
}


/* ==========================================================================
   DAFTAR ANTREAN — dipakai tab "Bayar nanti" dan "Online"
   ========================================================================== */

/// Panel daftar antrean: satu kartu dengan pemisah tipis antar baris.
/// Lebih padat dan mudah dipindai mata dibanding deretan kartu terpisah.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.count, required this.rowBuilder});

  final int count;
  final Widget Function(BuildContext context, int index) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (count == 0) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < count; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: theme.dividerColor.withValues(alpha: 0.75),
              ),
            rowBuilder(context, index),
          ],
        ],
      ),
    );
  }
}

/// Satu baris antrean.
///
/// Susunan informasi: kode pesanan (judul) → platform/tipe → pelanggan+waktu
/// → isi pesanan → aksi utama di kanan. Aksi destruktif tidak menempel di
/// baris, tapi lewat menu "..." supaya tidak salah tekan.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.title,
    this.tagLabel,
    this.tagColor,
    this.statusLabel,
    this.statusTone = PillTone.neutral,
    this.badge,
    required this.meta,
    required this.itemsText,
    this.note = '',
    this.itemsError = false,
    required this.totalText,
    required this.primaryLabel,
    required this.onPrimary,
    this.menuItems = const <PopupMenuEntry<String>>[],
    this.onMenuSelected,
    this.onTap,
  });

  final String title;
  final String? tagLabel;
  final Color? tagColor;
  final String? statusLabel;
  final PillTone statusTone;
  final Widget? badge;
  final String meta;
  final String itemsText;
  final String note;
  final bool itemsError;
  final String totalText;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String>? onMenuSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
            if (tagLabel != null)
              _TagChip(label: tagLabel!, color: tagColor ?? PosColors.skyDark),
            if (statusLabel != null)
              StatusPill(label: statusLabel!, tone: statusTone, radius: 7),
            ?badge,
          ],
        ),
        const SizedBox(height: 4),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: muted),
        ),
        const SizedBox(height: 3),
        Text(
          itemsText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: itemsError
                ? PosColors.red
                : theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );

    final total = Text(
      totalText,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        color: PosColors.skyDark,
      ),
    );

    final button = FilledButton(
      onPressed: onPrimary,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // Ukuran teks diatur di child agar font dari tema tidak ikut tertimpa.
      child: Text(
        primaryLabel,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );

    final more = menuItems.isEmpty
        ? null
        : PopupMenuButton<String>(
            tooltip: 'Aksi lain',
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            iconSize: 20,
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 190),
            onSelected: onMenuSelected,
            itemBuilder: (context) => menuItems,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 640) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        total,
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (more != null) ...[more, const SizedBox(width: 4)],
                            button,
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: total),
                      ?more,
                      const SizedBox(width: 4),
                      button,
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Label kecil berwarna (mis. platform GoFood/GrabFood/ShopeeFood).
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1.35,
        ),
      ),
    );
  }
}

/// Kode ambil saat pesanan sudah siap — dipakai untuk serah terima.
class _PickupBadge extends StatelessWidget {
  const _PickupBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = toneOf(context, PillTone.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 12, color: colors.foreground),
          const SizedBox(width: 3),
          Text(
            code,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: colors.foreground,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/* ==========================================================================
   BAYAR NANTI
   ========================================================================== */

class _PendingList extends StatelessWidget {
  const _PendingList({required this.onOpenCashier});

  final VoidCallback onOpenCashier;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final pending = [...controller.pendingOrders]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (pending.isEmpty) {
      return const EmptyState(
        icon: Icons.pause_circle_outline_rounded,
        title: 'Tidak ada pesanan menunggu',
        message: 'Pesanan yang disimpan lewat "Simpan nanti" akan muncul di sini.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _QueuePanel(
          count: pending.length,
          rowBuilder: (context, index) => _PendingRow(
            order: pending[index],
            onOpenCashier: onOpenCashier,
          ),
        ),
      ],
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.order, required this.onOpenCashier});

  final PendingOrder order;
  final VoidCallback onOpenCashier;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final missing = order.items
        .where((item) => controller.productById(item.productId) == null)
        .length;
    final itemsText = order.items
        .map((item) => '${item.qty}× ${item.name}')
        .join(', ');
    final meta = [
      formatTime(order.createdAt),
      order.orderType == 'takeaway' ? 'Dibungkus' : 'Makan di tempat',
      if (order.tableNumber.isNotEmpty) 'Meja ${order.tableNumber}',
    ].join(' · ');

    return _QueueRow(
      title: order.id,
      statusLabel: 'Belum bayar',
      statusTone: PillTone.warning,
      badge: missing > 0
          ? StatusPill(
              label: '$missing menu tidak ada',
              tone: PillTone.danger,
              icon: Icons.warning_amber_rounded,
              radius: 7,
            )
          : null,
      meta: meta,
      itemsText: itemsText,
      note: order.note.trim().isEmpty ? '' : 'Catatan: ${order.note.trim()}',
      totalText: formatRupiah(order.total),
      primaryLabel: 'Lanjutkan',
      onPrimary: () => _resume(context, controller),
      menuItems: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'finish', child: Text('Selesai dibuat')),
        PopupMenuItem<String>(value: 'cancel', child: Text('Batalkan')),
      ],
      onMenuSelected: (value) {
        if (value == 'finish') _finish(context, controller);
        if (value == 'cancel') _cancel(context, controller);
      },
    );
  }

  Future<void> _resume(BuildContext context, AppController controller) async {
    final ok = await controller.resumePendingOrder(order.id);
    if (ok && context.mounted) {
      onOpenCashier();
    }
  }

  Future<void> _finish(BuildContext context, AppController controller) async {
    final ok = await confirmDialog(
      context,
      title: 'Selesaikan pesanan?',
      message:
          'Pesanan ${order.id} ditandai selesai dibuat dan dihapus dari antrean. '
          'Transaksi TIDAK tercatat sebagai penjualan.',
      confirmLabel: 'Selesai',
    );
    if (ok) await controller.finishPendingOrder(order.id);
  }

  Future<void> _cancel(BuildContext context, AppController controller) async {
    final paid = order.status == 'preparing';
    final ok = await confirmDialog(
      context,
      title: 'Batalkan pesanan?',
      message: paid
          ? 'Batalkan pesanan ${order.id}? Pesanan sudah dibayar dan akan '
              'dihapus dari antrean tanpa masuk riwayat penjualan.'
          : 'Batalkan pesanan ${order.id}? Data keranjang/riwayat tidak akan '
              'tersimpan.',
      confirmLabel: 'Batalkan pesanan',
      danger: true,
    );
    if (ok) await controller.cancelPendingOrder(order.id);
  }
}

/* ==========================================================================
   PESANAN ONLINE
   ========================================================================== */

class _OnlineList extends StatelessWidget {
  const _OnlineList();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final counts = controller.onlineStatusCounts;
    final orders = [...controller.visibleOnlineOrders]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _QueueFilterBar(
                  children: [
                    for (final status in const ['baru', 'dibuat', 'siap'])
                      _QueueChip(
                        label: kOnlineStatus[status] ?? status,
                        count: counts[status] ?? 0,
                        selected: controller.onlineStatusFilter == status,
                        onTap: () => controller.setOnlineStatusFilter(status),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PlatformFilterButton(
                current: controller.onlinePlatformFilter,
                onSelected: controller.setOnlinePlatformFilter,
              ),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? EmptyState(
                  icon: Icons.delivery_dining_rounded,
                  title:
                      'Tidak ada pesanan ${kOnlineStatus[controller.onlineStatusFilter]?.toLowerCase() ?? ''}',
                  message:
                      'Pesanan dari GoFood, GrabFood, dan ShopeeFood muncul di sini.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: [
                    _QueuePanel(
                      count: orders.length,
                      rowBuilder: (context, index) =>
                          _OnlineRow(order: orders[index]),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _QueueFilterBar extends StatelessWidget {
  const _QueueFilterBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          children[i],
        ],
      ]),
    );
  }
}

/// Chip filter status ala `.queue-chip` di iPoS web.
class _QueueChip extends StatelessWidget {
  const _QueueChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected ? PosColors.skyDark : theme.cardTheme.color;
    final fg = selected ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final border = selected ? PosColors.skyDark : theme.dividerColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  height: 1.1,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Filter platform dipadatkan jadi satu tombol dropdown, bukan deretan chip
/// panjang, supaya area daftar tetap lega.
class _PlatformFilterButton extends StatelessWidget {
  const _PlatformFilterButton({required this.current, required this.onSelected});

  final String current;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = current != 'all';
    final label = active ? (kOnlinePlatforms[current] ?? current) : 'Semua platform';
    final fg = active
        ? Colors.white
        : theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return PopupMenuButton<String>(
      tooltip: 'Filter platform',
      initialValue: current,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem<String>(value: 'all', child: Text('Semua platform')),
        for (final platform in const ['gofood', 'grab', 'shopee', 'other'])
          PopupMenuItem<String>(
            value: platform,
            child: Text(kOnlinePlatforms[platform] ?? platform),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? PosColors.skyDark : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? PosColors.skyDark : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_rounded, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

class _OnlineRow extends StatelessWidget {
  const _OnlineRow({required this.order});

  final OnlineOrder order;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final items = controller.resolveOnlineItems(order);
    final total = controller.onlineTotal(order);
    final platform = kOnlinePlatforms[order.source] ?? kOnlinePlatforms['other']!;
    final itemsText = items.isEmpty
        ? 'Item tidak ditemukan di katalog menu.'
        : items.map((item) => '${item.qty}× ${item.name}').join(', ');
    final meta = [
      if (order.customer.isNotEmpty) order.customer,
      formatTime(order.createdAt),
    ].join(' · ');

    return _QueueRow(
      title: order.code.isEmpty ? order.id : order.code,
      tagLabel: platform,
      tagColor: _platformColor(order.source),
      statusLabel: kOnlineStatus[order.status] ?? order.status,
      statusTone: _statusTone(order.status),
      badge: (order.status == 'siap' && order.pickupCode.isNotEmpty)
          ? _PickupBadge(code: order.pickupCode)
          : null,
      meta: meta,
      itemsText: itemsText,
      itemsError: items.isEmpty,
      note: order.note.trim().isEmpty ? '' : 'Catatan: ${order.note.trim()}',
      totalText: formatRupiah(total),
      primaryLabel: _nextShortLabel(order.status),
      onPrimary: () => _advanceOnline(context, order),
      menuItems: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'detail', child: Text('Lihat detail')),
        PopupMenuItem<String>(value: 'print', child: Text('Cetak nota')),
        PopupMenuItem<String>(value: 'reject', child: Text('Tolak / batalkan')),
      ],
      onMenuSelected: (value) async {
        switch (value) {
          case 'detail':
            await _showOnlineDetail(context, order);
          case 'print':
            await controller.printOnlineTicket(order);
          case 'reject':
            await _rejectOnline(context, order);
        }
      },
      onTap: () => _showOnlineDetail(context, order),
    );
  }
}

/// Label tombol ringkas untuk daftar (detail memakai versi panjang).
String _nextShortLabel(String status) {
  switch (status) {
    case 'baru':
      return 'Terima';
    case 'dibuat':
      return 'Siap';
    case 'siap':
      return 'Selesaikan';
    default:
      return 'Selesai';
  }
}

Color _platformColor(String source) {
  switch (source) {
    case 'gofood':
      return const Color(0xFF00880D);
    case 'grab':
      return const Color(0xFF00B14F);
    case 'shopee':
      return const Color(0xFFEE4D2D);
    case 'maxim':
      return const Color(0xFF475569);
    default:
      return PosColors.ink;
  }
}

PillTone _statusTone(String status) {
  switch (status) {
    case 'baru':
      return PillTone.warning;
    case 'dibuat':
      return PillTone.info;
    case 'siap':
      return PillTone.success;
    default:
      return PillTone.neutral;
  }
}

String _nextLabel(String status) {
  switch (status) {
    case 'baru':
      return 'Terima pesanan';
    case 'dibuat':
      return 'Tandai siap';
    case 'siap':
      return 'Selesaikan';
    default:
      return 'Selesai';
  }
}

Future<void> _showOnlineDetail(BuildContext context, OnlineOrder order) {
  return showAppSheet<void>(
    context,
    builder: (context) => _OnlineDetailSheet(orderId: order.id),
  );
}

class _OnlineDetailSheet extends StatelessWidget {
  const _OnlineDetailSheet({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final order = controller.onlineOrders
        .where((o) => o.id == orderId)
        .cast<OnlineOrder?>()
        .firstWhere((_) => true, orElse: () => null);
    if (order == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Pesanan tidak ditemukan.'),
      );
    }

    final items = controller.resolveOnlineItems(order);
    final total = controller.onlineTotal(order);
    final platform = kOnlinePlatforms[order.source] ?? kOnlinePlatforms['other']!;
    final nextLabel = _nextLabel(order.status);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              order.code.isEmpty ? order.id : order.code,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            _TagChip(
                              label: platform,
                              color: _platformColor(order.source),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${order.customer.isEmpty ? 'Pelanggan' : order.customer} · ${formatTime(order.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: kOnlineStatus[order.status] ?? order.status,
                    tone: _statusTone(order.status),
                    radius: 7,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                const Text(
                  'Item tidak ditemukan di katalog menu.',
                  style: TextStyle(fontSize: 12.5, color: PosColors.red),
                )
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.qty}×',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRupiah(item.total),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (order.note.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Catatan: ${order.note.trim()}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (order.status == 'siap' && order.pickupCode.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: toneOf(context, PillTone.success).background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Kode ambil: ${order.pickupCode}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: toneOf(context, PillTone.success).foreground,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const DashedDivider(height: 14),
              InfoRow(label: 'Total', value: formatRupiah(total), bold: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => controller.printOnlineTicket(order),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Cetak nota'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await Future<void>.delayed(const Duration(milliseconds: 120));
                      if (context.mounted) await _rejectOnline(context, order);
                    },
                    style: TextButton.styleFrom(foregroundColor: PosColors.red),
                    child: Text(order.status == 'baru' ? 'Tolak' : 'Batalkan'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await _advanceOnline(context, order);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
                child: Text(nextLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _advanceOnline(BuildContext context, OnlineOrder order) async {
  final controller = context.read<AppController>();
  if (order.status == 'siap') {
    final ok = await confirmDialog(
      context,
      title: 'Selesaikan pesanan?',
      message:
          'Pesanan ${order.code} akan dicatat sebagai penjualan di laporan dan stok menu dikurangi.',
      confirmLabel: 'Selesaikan',
    );
    if (!ok) return;
  }
  await controller.advanceOnlineOrder(order.id);
}

Future<void> _rejectOnline(BuildContext context, OnlineOrder order) async {
  final controller = context.read<AppController>();
  final reason = TextEditingController(
    text: controller.settings.onlineRejectionMessage,
  );
  final platform = kOnlinePlatforms[order.source] ?? kOnlinePlatforms['other']!;
  final label = order.code.isEmpty ? order.id : order.code;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Alasan membatalkan pesanan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · $platform',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLength: 200,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Pesan untuk pelanggan',
              helperText:
                  'Jika dibiarkan kosong, alasan "Mohon maaf stok habis" akan digunakan.',
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Kembali'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: PosColors.red),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Tolak pesanan'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.rejectOnlineOrder(order.id, reason.text);
  }
  reason.dispose();
}
