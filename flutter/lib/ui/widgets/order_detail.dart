import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/print_service.dart';
import '../../state/app_controller.dart';
import 'common.dart';

Future<void> showOrderDetail(
  BuildContext context,
  Order order, {
  bool allowDelete = false,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) =>
        _OrderDetailSheet(order: order, allowDelete: allowDelete),
  );
}

class _OrderDetailSheet extends StatelessWidget {
  const _OrderDetailSheet({required this.order, required this.allowDelete});

  final Order order;
  final bool allowDelete;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detail transaksi',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          order.id,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: ReceiptBuilder.paymentLabel(order.payment),
                    tone: order.payment == 'cash' ? PillTone.success : PillTone.info,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusPill(
                    label: ReceiptBuilder.orderTypeLabel(order.orderType),
                    tone: PillTone.neutral,
                  ),
                  if (order.tableNumber.isNotEmpty)
                    StatusPill(
                      label: 'Meja ${order.tableNumber}',
                      tone: PillTone.neutral,
                    ),
                  StatusPill(
                    label: formatDateTime(order.createdAt),
                    tone: PillTone.neutral,
                    icon: Icons.schedule_rounded,
                  ),
                  if (order.cashier.isNotEmpty)
                    StatusPill(
                      label: order.cashier,
                      tone: PillTone.neutral,
                      icon: Icons.person_outline_rounded,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ...order.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${item.qty}×',
                          style: TextStyle(
                            fontSize: 11,
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
                            Text(
                              item.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (item.note.trim().isNotEmpty)
                              Text(
                                item.note.trim(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRupiah(item.total),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const DashedDivider(),
              InfoRow(label: 'Subtotal', value: formatRupiah(order.subtotal)),
              if (order.discount > 0)
                InfoRow(
                  label: 'Diskon',
                  value: '-${formatRupiah(order.discount)}',
                  valueColor: PosColors.green,
                ),
              InfoRow(label: 'Total', value: formatRupiah(order.total), bold: true),
              if (order.payment == 'cash') ...[
                InfoRow(label: 'Tunai', value: formatRupiah(order.paidAmount)),
                InfoRow(label: 'Kembali', value: formatRupiah(order.changeAmount)),
              ],
              if (order.note.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Catatan: ${order.note.trim()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => controller.shareReceiptPdf(order),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => controller.printReceipt(order),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Cetak struk'),
                    ),
                  ),
                ],
              ),
              if (allowDelete) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Hapus transaksi?',
                      message:
                          'Transaksi ${order.id} dihapus dari laporan. Stok menu TIDAK dikembalikan.',
                      confirmLabel: 'Hapus',
                      danger: true,
                    );
                    if (!ok) return;
                    await controller.deleteOrder(order.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Hapus transaksi'),
                  style: TextButton.styleFrom(foregroundColor: PosColors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
