import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/print_service.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';
import 'widgets/order_detail.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  /// 0 = Beranda, 1 = Kasir, 2 = Pesanan, 3 = Menu, 4 = Laporan.
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final today = controller.ordersForDate(dateKey());
    final revenue = today.fold<int>(0, (sum, order) => sum + order.total);
    final items = today.fold<int>(0, (sum, order) => sum + order.itemCount);
    final average = today.isEmpty ? 0 : revenue / today.length;
    final recent = [...today]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentSlice = recent.take(6).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        PageHeading(
          kicker: 'Halo, ${controller.user?.name ?? 'Kasir'} 👋',
          title: 'Ringkasan hari ini',
          subtitle: 'Semua transaksi hari ini akan muncul di sini.',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                    ? 2
                    : 2;
            const spacing = 10.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cards = [
              StatCard(
                label: 'Omzet hari ini',
                value: formatRupiah(revenue),
                hint: '${formatNumber(today.length)} transaksi selesai',
                icon: Icons.payments_rounded,
                primary: true,
              ),
              StatCard(
                label: 'Transaksi',
                value: formatNumber(today.length),
                hint: 'pesanan hari ini',
                icon: Icons.receipt_long_rounded,
              ),
              StatCard(
                label: 'Rata-rata',
                value: formatRupiah(average),
                hint: 'per transaksi',
                icon: Icons.trending_up_rounded,
              ),
              StatCard(
                label: 'Item terjual',
                value: formatNumber(items),
                hint: 'item hari ini',
                icon: Icons.local_mall_rounded,
              ),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _RecentPanel(
          orders: recentSlice,
          showHeader: false,
          onNavigate: onNavigate,
          controller: controller,
        ),
        const SizedBox(height: 16),
        _QuickPanel(
          controller: controller,
          onNavigate: onNavigate,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              Icons.cloud_done_rounded,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                controller.syncStatus?.label ?? 'Lokal',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            Text(
              formatDateLong(controller.now),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({
    required this.orders,
    required this.showHeader,
    required this.onNavigate,
    required this.controller,
  });

  final List<Order> orders;
  final bool showHeader;
  final ValueChanged<int> onNavigate;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      kicker: 'Aktivitas terbaru',
      title: 'Transaksi terakhir',
      trailing: TextButton(
        onPressed: () => onNavigate(4),
        child: const Text('Lihat semua'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: orders.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Belum ada transaksi hari ini',
              message: 'Mulai dari Kasir untuk membuat pesanan pertama.',
            )
          : Column(
              children: [
                if (showHeader) const _RecentTableHeader(),
                for (final order in orders)
                  _RecentOrderRow(
                    order: order,
                    onTap: () => showOrderDetail(
                      context,
                      order,
                      allowDelete: controller.isOwner,
                    ),
                    onPrint: () => controller.printReceipt(order),
                  ),
              ],
            ),
    );
  }
}

class _RecentTableHeader extends StatelessWidget {
  const _RecentTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 44, child: Text('WAKTU', style: style)),
              Expanded(child: Text('TRANSAKSI', style: style)),
              Text('TOTAL', style: style),
              const SizedBox(width: 44),
            ],
          ),
          Divider(height: 12, color: theme.dividerColor),
        ],
      ),
    );
  }
}

class _QuickPanel extends StatelessWidget {
  const _QuickPanel({required this.controller, required this.onNavigate});

  final AppController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      kicker: 'Akses cepat',
      title: 'Yang perlu dilakukan',
      child: Column(
        children: [
          _QuickAction(
            icon: Icons.point_of_sale_rounded,
            color: PosColors.sky,
            title: 'Transaksi baru',
            subtitle: 'Buat pesanan pelanggan',
            onTap: () => onNavigate(1),
          ),
          const SizedBox(height: 10),
          _QuickAction(
            icon: Icons.restaurant_menu_rounded,
            color: PosColors.green,
            title: 'Pesanan berjalan',
            subtitle: '${controller.pendingOrders.length} bayar nanti · '
                '${controller.onlineOrders.where((order) => order.status != 'selesai').length} online',
            onTap: () => onNavigate(2),
          ),
          if (controller.isOwner) ...[
            const SizedBox(height: 10),
            _QuickAction(
              icon: Icons.inventory_2_rounded,
              color: PosColors.orange,
              title: 'Kelola menu',
              subtitle: 'Harga, stok, dan ketersediaan',
              onTap: () => onNavigate(3),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({
    required this.order,
    required this.onTap,
    required this.onPrint,
  });

  final Order order;
  final VoidCallback onTap;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items =
        order.items.map((item) => '${item.qty}× ${item.name}').join(', ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                formatTime(order.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupiah(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  ReceiptBuilder.paymentLabel(order.payment),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: onPrint,
              visualDensity: VisualDensity.compact,
              tooltip: 'Cetak ulang',
              icon: const Icon(Icons.print_outlined, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
          color: theme.colorScheme.surface.withValues(alpha: 0.4),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
