import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/print_service.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';
import 'widgets/order_detail.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from;
  late DateTime _to;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = _from;
  }

  /// Senin pada minggu berjalan (0 = Senin, sama seperti `startOfWeek` web).
  static DateTime _startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final offset = (day.weekday + 6) % 7;
    return day.subtract(Duration(days: offset));
  }

  void _quick(String preset) {
    final today = DateTime.now();
    var from = DateTime(today.year, today.month, today.day);
    var to = from;
    switch (preset) {
      case 'yesterday':
        from = DateTime(today.year, today.month, today.day - 1);
        to = from;
        break;
      case '7':
        from = from.subtract(const Duration(days: 6));
        break;
      case '30':
        from = from.subtract(const Duration(days: 29));
        break;
      case 'month':
        from = DateTime(today.year, today.month, 1);
        break;
    }
    setState(() {
      _from = from;
      _to = to;
      _error = null;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: isFrom ? 'Tanggal awal' : 'Tanggal akhir',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
      _error = null;
    });
  }

  Future<void> _export(String kind) async {
    if (_exporting) return;
    final controller = context.read<AppController>();
    final from = dateKey(_from);
    final to = dateKey(_to);
    if (from.compareTo(to) > 0) {
      setState(() => _error = 'Tanggal awal tidak boleh lebih besar dari tanggal akhir.');
      return;
    }
    setState(() => _exporting = true);
    await controller.exportReport(from: from, to: to, kindLabel: kind);
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final from = dateKey(_from);
    final to = dateKey(_to);
    final orders = controller.filteredOrders(from, to)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final revenue = orders.fold<int>(0, (sum, order) => sum + order.total);
    final items = orders.fold<int>(0, (sum, order) => sum + order.itemCount);
    final average = orders.isEmpty ? 0 : revenue / orders.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        PageHeading(
          kicker: 'Laporan',
          title: 'Laporan penjualan',
          subtitle: '${formatDateShort(_from)} — ${formatDateShort(_to)} · '
              '${formatNumber(orders.length)} transaksi',
          actions: [
            OutlinedButton.icon(
              onPressed: _exporting
                  ? null
                  : () {
                      final today = DateTime.now();
                      setState(() {
                        _from = DateTime(today.year, today.month, today.day);
                        _to = _from;
                        _error = null;
                      });
                      _export('Harian');
                    },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Hari ini'),
            ),
            OutlinedButton.icon(
              onPressed: _exporting
                  ? null
                  : () {
                      final today = DateTime.now();
                      setState(() {
                        // Sama seperti web: minggu berjalan Senin–Minggu,
                        // bukan 7 hari terakhir yang bergulir.
                        _from = _startOfWeek(today);
                        _to = _from.add(const Duration(days: 6));
                        _error = null;
                      });
                      _export('Mingguan');
                    },
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: const Text('Mingguan'),
            ),
            FilledButton.icon(
              onPressed: _exporting ? null : () => _export('Rentang'),
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.table_view_rounded, size: 18),
              label: const Text('Export Excel'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          kicker: 'Periode',
          title: 'Pilih rentang tanggal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Dari',
                      value: formatDateShort(_from),
                      onTap: () => _pickDate(isFrom: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 16),
                  ),
                  Expanded(
                    child: _DateField(
                      label: 'Sampai',
                      value: formatDateShort(_to),
                      onTap: () => _pickDate(isFrom: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Cepat',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  for (final preset in const [
                    ('today', 'Hari ini'),
                    ('yesterday', 'Kemarin'),
                    ('7', '7 hari'),
                    ('30', '30 hari'),
                    ('month', 'Bulan ini'),
                  ])
                    ActionChip(
                      label: Text(preset.$2),
                      onPressed: () => _quick(preset.$1),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: PosColors.red),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 4 : 2;
            const spacing = 10.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Total omzet',
                    value: formatRupiah(revenue),
                    hint: '${formatNumber(orders.length)} transaksi',
                    icon: Icons.payments_rounded,
                    primary: true,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Transaksi',
                    value: formatNumber(orders.length),
                    hint: 'pesanan lunas',
                    icon: Icons.receipt_long_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Item terjual',
                    value: formatNumber(items),
                    hint: 'item',
                    icon: Icons.local_mall_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Rata-rata',
                    value: formatRupiah(average),
                    hint: 'per transaksi',
                    icon: Icons.trending_up_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        SectionCard(
          kicker: 'Rincian periode',
          title: 'Transaksi',
          trailing: Text(
            '${formatNumber(orders.length)} baris',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: orders.isEmpty
              ? const EmptyState(
                  icon: Icons.bar_chart_rounded,
                  title: 'Belum ada transaksi',
                  message: 'Tidak ada transaksi lunas pada rentang tanggal ini.',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 640;
                    return Column(
                      children: [
                        if (wide) const _ReportTableHeader(),
                        for (final order in orders) _ReportRow(order: order),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTableHeader extends StatelessWidget {
  const _ReportTableHeader();

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
              SizedBox(width: 56, child: Text('WAKTU', style: style)),
              const SizedBox(width: 6),
              Expanded(child: Text('TRANSAKSI', style: style)),
              const SizedBox(width: 8),
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

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showOrderDetail(
        context,
        order,
        allowDelete: controller.isOwner,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTime(order.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatDayMonth(order.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    order.items
                        .map((item) => '${item.qty}× ${item.name}')
                        .join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
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
                Text(
                  ReceiptBuilder.paymentLabel(order.payment),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Cetak ulang',
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.printReceipt(order),
              icon: const Icon(Icons.print_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
