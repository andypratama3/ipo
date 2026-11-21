import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/print_service.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openCart() async {
    final controller = context.read<AppController>();
    if (controller.cart.isEmpty) return;
    final checkout = await showAppSheet<bool>(
      context,
      builder: (context) => const _CartSheet(),
    );
    if (checkout == true && mounted) {
      await _openCheckout();
    }
  }

  Future<void> _openCheckout() async {
    final controller = context.read<AppController>();
    if (controller.cart.isEmpty) return;
    final order = await showAppSheet<Order>(
      context,
      builder: (context) => const _CheckoutSheet(),
    );
    if (order != null && mounted) {
      await showAppSheet<void>(
        context,
        builder: (context) => _ReceiptSheet(order: order),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Column(
      children: [
        Expanded(child: _ProductPanel(search: _search, panel: false)),
        if (controller.cart.isNotEmpty) _CartBar(onTap: _openCart),
      ],
    );
  }
}

/* ==========================================================================
   KATALOG PRODUK
   ========================================================================== */

class _ProductPanel extends StatelessWidget {
  const _ProductPanel({required this.search, required this.panel});

  final TextEditingController search;
  final bool panel;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final products = controller.visibleProducts;
    final categories = [
      Category(id: 'semua', label: 'Semua', emoji: '🍽️'),
      ...controller.categories,
    ];

    final toolbar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: search,
          onChanged: controller.setSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Cari menu…',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: controller.search.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Bersihkan',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      search.clear();
                      controller.setSearch('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              final active = controller.category == category.id;
              return ChoiceChip(
                selected: active,
                onSelected: (_) => controller.setCategory(category.id),
                avatar: Text(
                  category.emoji,
                  style: const TextStyle(fontSize: 14),
                ),
                label: Text(category.label),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? Colors.white
                      : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                selectedColor: PosColors.sky,
                backgroundColor: theme.cardTheme.color,
                side: BorderSide(
                  color: active ? PosColors.sky : theme.dividerColor,
                ),
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            },
          ),
        ),
      ],
    );

    final grid = products.isEmpty
        ? EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Menu tidak ditemukan',
            message: controller.search.isEmpty
                ? 'Belum ada menu tersedia di kategori ini.'
                : 'Coba kata kunci lain atau pilih kategori "Semua".',
          )
        : GridView.builder(
            padding: panel ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 128,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final availability = controller.availability(product);
              return ProductTile(
                emoji: product.emoji,
                name: product.name,
                price: product.price,
                stockLabel:
                    product.stock == null ? null : 'Sisa ${product.stock}',
                available: availability.canSell,
                onTap: () async {
                  final added = await controller.addToCart(product.id);
                  if (!added && context.mounted) {
                    showAppSnack(context, availability.label);
                  }
                },
              );
            },
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const SizedBox(height: 12),
        Expanded(child: grid),
      ],
    );

    if (!panel) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: content,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: content,
      ),
    );
  }
}

/* ==========================================================================
   BILAH KERANJANG (HP)
   ========================================================================== */

class _CartBar extends StatelessWidget {
  const _CartBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    return Material(
      color: theme.cardTheme.color,
      elevation: 12,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PosColors.sky.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.shopping_bag_rounded,
                        color: PosColors.sky,
                      ),
                      Positioned(
                        right: -8,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: PosColors.orange,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${controller.cartCount}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${controller.cartCount} item',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        formatRupiah(controller.cartTotals.total),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onTap,
                  child: const Text('Lihat'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ==========================================================================
   KERANJANG
   ========================================================================== */

class _CartSheet extends StatelessWidget {
  const _CartSheet();

  @override
  Widget build(BuildContext context) {
    return _CartPanel(
      embedded: false,
      onCheckout: () => Navigator.of(context).pop(true),
    );
  }
}

class _CartPanel extends StatefulWidget {
  const _CartPanel({required this.onCheckout, this.embedded = false});

  final VoidCallback onCheckout;
  final bool embedded;

  @override
  State<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<_CartPanel> {
  late final AppController _controller;
  late final TextEditingController _discount;
  late final TextEditingController _note;
  late final TextEditingController _table;

  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _discount = TextEditingController(
      text: _controller.cartDiscount == 0 ? '' : '${_controller.cartDiscount}',
    );
    _note = TextEditingController(text: _controller.cartNote);
    _table = TextEditingController(text: _controller.tableNumber);
    _controller.addListener(_syncAfterCheckout);
  }

  void _syncAfterCheckout() {
    if (!mounted || _controller.cart.isNotEmpty) return;
    if (_discount.text.isNotEmpty) _discount.clear();
    if (_note.text.isNotEmpty) _note.clear();
    if (_table.text.isNotEmpty) _table.clear();
  }

  @override
  void dispose() {
    _controller.removeListener(_syncAfterCheckout);
    _discount.dispose();
    _note.dispose();
    _table.dispose();
    super.dispose();
  }

  Future<void> _clear(BuildContext context, AppController controller) async {
    final ok = await confirmDialog(
      context,
      title: 'Kosongkan keranjang?',
      message: 'Semua item di keranjang akan dihapus.',
      confirmLabel: 'Kosongkan',
      danger: true,
    );
    if (ok) await controller.clearCart();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final totals = controller.cartTotals;
    final cart = controller.cart;

    final middle = <Widget>[
      if (cart.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Column(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 30,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keranjang kosong',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Pilih menu untuk mulai transaksi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        )
      else
        ...cart.map((item) => _CartLine(item: item)),
      const SizedBox(height: 10),
      _OrderTypeToggle(controller: controller),
      if (controller.orderType == 'dine-in') ...[
        const SizedBox(height: 10),
        TextField(
          controller: _table,
          onChanged: controller.setTableNumber,
          decoration: const InputDecoration(
            hintText: 'Nomor meja (opsional)',
            prefixIcon: Icon(Icons.tag_rounded),
            isDense: true,
          ),
        ),
      ],
      const SizedBox(height: 10),
      TextField(
        controller: _discount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (value) =>
            controller.setCartDiscount(int.tryParse(value) ?? 0),
        decoration: InputDecoration(
          hintText: 'Diskon (Rp)',
          prefixIcon: const Icon(Icons.local_offer_outlined),
          isDense: true,
          helperText: totals.discount > 0
              ? 'Diskon ${formatRupiah(totals.discount)} diterapkan'
              : null,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _note,
        maxLength: 120,
        onChanged: controller.setCartNote,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText: 'Catatan pesanan (opsional)',
          isDense: true,
        ),
      ),
    ];

    final scroll = ListView(
      shrinkWrap: !widget.embedded,
      padding: EdgeInsets.zero,
      children: middle,
    );

    final content = Column(
      mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Keranjang',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            if (cart.isNotEmpty)
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: PosColors.sky,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${controller.cartCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed:
                  cart.isEmpty ? null : () => _clear(context, controller),
              icon: const Icon(Icons.delete_sweep_rounded, size: 17),
              label: const Text('Kosongkan'),
              style: TextButton.styleFrom(
                foregroundColor: PosColors.red,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (widget.embedded)
          Expanded(child: scroll)
        else
          Flexible(child: scroll),
        const SizedBox(height: 4),
        const DashedDivider(height: 14),
        InfoRow(label: 'Subtotal', value: formatRupiah(totals.subtotal)),
        if (totals.discount > 0)
          InfoRow(
            label: 'Diskon',
            value: '-${formatRupiah(totals.discount)}',
            valueColor: PosColors.green,
          ),
        InfoRow(label: 'Total', value: formatRupiah(totals.total), bold: true),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: cart.isEmpty
              ? null
              : () async {
                  final held = await controller.holdOrder();
                  if (held && context.mounted && !widget.embedded) {
                    Navigator.of(context).pop();
                  }
                },
          icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
          label: const Text('Simpan nanti'),
        ),
        const SizedBox(height: 8),
        _CheckoutButton(
          onTap: cart.isEmpty ? null : widget.onCheckout,
          total: totals.total,
        ),
      ],
    );

    if (widget.embedded) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      );
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: content,
        ),
      ),
    );
  }
}

class _OrderTypeToggle extends StatelessWidget {
  const _OrderTypeToggle({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget item(String value, String label, IconData icon) {
      final active = controller.orderType == value;
      final color = active
          ? PosColors.skyDark
          : theme.colorScheme.onSurface.withValues(alpha: 0.55);
      return Expanded(
        child: InkWell(
          onTap: () => controller.setOrderType(value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? theme.cardTheme.color : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          item('dine-in', 'Makan di tempat', Icons.table_restaurant_rounded),
          const SizedBox(width: 3),
          item('takeaway', 'Dibungkus', Icons.takeout_dining_rounded),
        ],
      ),
    );
  }
}

class _CheckoutButton extends StatelessWidget {
  const _CheckoutButton({required this.onTap, required this.total});

  final VoidCallback? onTap;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [PosColors.green, Color(0xFF0F8A5B)],
            ),
            boxShadow: [
              BoxShadow(
                color: PosColors.green.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Lanjut ke pembayaran',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    formatRupiah(total),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final missing = controller.cartItemMissing(item);
    final noteOpen = controller.cartNoteOpenId == item.productId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: missing ? PosColors.red.withValues(alpha: 0.5) : theme.dividerColor,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.cartItemEmoji(item),
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.cartItemName(item),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (missing)
                      const Text(
                        'Menu sudah tidak ada di katalog',
                        style: TextStyle(fontSize: 11, color: PosColors.red),
                      )
                    else
                      Text(
                        formatRupiah(controller.cartItemPrice(item)),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _QtyStepper(item: item),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => controller.toggleCartNote(item.productId),
                    icon: Icon(
                      noteOpen
                          ? Icons.expand_less_rounded
                          : Icons.edit_note_rounded,
                      size: 17,
                    ),
                    label: Text(
                      item.note.trim().isEmpty
                          ? 'Catatan item'
                          : item.note.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: item.note.trim().isEmpty
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
                          : PosColors.skyDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRupiah(controller.cartItemPrice(item) * item.qty),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (noteOpen)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextFormField(
                key: ValueKey('cart-note-${item.productId}-$noteOpen'),
                initialValue: item.note,
                maxLength: 120,
                onChanged: (value) => controller.setCartItemNote(item.productId, value),
                decoration: const InputDecoration(
                  hintText: 'mis. tanpa sayur, sambal dipisah',
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => controller.changeCartQuantity(item.productId, -1),
            icon: const Icon(Icons.remove_rounded, size: 17),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          SizedBox(
            width: 22,
            child: Text(
              '${item.qty}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => controller.changeCartQuantity(item.productId, 1),
            icon: const Icon(Icons.add_rounded, size: 17),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/* ==========================================================================
   PEMBAYARAN
   ========================================================================== */

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet();

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  String _payment = 'cash';
  final _cash = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _payment = context.read<AppController>().selectedPayment;
    if (!const ['cash', 'qris', 'transfer', 'card'].contains(_payment)) {
      _payment = 'cash';
    }
  }

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  int get _received => int.tryParse(_cash.text) ?? 0;

  Future<void> _submit(AppController controller) async {
    if (_busy) return;
    final totals = controller.cartTotals;
    if (_payment == 'cash' && _received < totals.total) {
      showAppSnack(context, 'Uang diterima kurang dari total.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: _payment == 'cash'
          ? 'Uang tunai sudah diterima?'
          : 'Pembayaran sudah diterima?',
      message: _payment == 'cash'
          ? 'Pastikan uang tunai sudah diterima dari pelanggan sebelum transaksi diselesaikan.'
          : _payment == 'qris'
              ? 'Pastikan QRIS sudah dibayar pelanggan sebelum transaksi diselesaikan.'
              : _payment == 'transfer'
                  ? 'Pastikan transfer sudah diterima sebelum menyelesaikan transaksi.'
                  : 'Pastikan pembayaran sudah diterima sebelum menyelesaikan transaksi.',
      confirmLabel: 'Ya, selesaikan',
    );
    if (!ok) return;
    setState(() => _busy = true);
    controller.selectedPayment = _payment;
    final order = await controller.completePayment(
      payment: _payment,
      cashReceived: _payment == 'cash' ? _received : totals.total,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (order != null) {
      Navigator.of(context).pop(order);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final totals = controller.cartTotals;
    final change = _payment == 'cash' ? _received - totals.total : 0;
    final qrisPayload = controller.dynamicQrisFor(totals.total);
    final methods = const [
      ('cash', 'Tunai', Icons.payments_rounded, PosColors.green),
      ('qris', 'QRIS', Icons.qr_code_2_rounded, PosColors.sky),
      ('transfer', 'Transfer', Icons.account_balance_rounded, PosColors.orange),
      ('card', 'Kartu', Icons.credit_card_rounded, PosColors.skyDark),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pilih pembayaran',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${controller.cartCount} item · total ${formatRupiah(totals.total)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [PosColors.skyDark, PosColors.sky],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'TOTAL TAGIHAN',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatRupiah(totals.total),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.8,
                      ),
                    ),
                    if (totals.discount > 0)
                      Text(
                        'Hemat ${formatRupiah(totals.discount)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final method in methods)
                    _PaymentOption(
                      label: method.$2,
                      icon: method.$3,
                      color: method.$4,
                      active: _payment == method.$1,
                      onTap: () => setState(() => _payment = method.$1),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_payment == 'cash') ...[
                LabeledField(
                  label: 'Uang diterima',
                  child: TextField(
                    controller: _cash,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '0',
                      prefixText: 'Rp ',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amount in _quickAmounts(totals.total))
                      ActionChip(
                        label: Text(amount == totals.total
                            ? 'Uang pas'
                            : formatNumber(amount)),
                        onPressed: () {
                          _cash.text = '$amount';
                          setState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: change < 0
                        ? toneOf(context, PillTone.danger).background
                        : toneOf(context, PillTone.success).background,
                  ),
                  child: Row(
                    children: [
                      Text(
                        change < 0 ? 'Kurang' : 'Kembalian',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        formatRupiah(change.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: change < 0
                              ? toneOf(context, PillTone.danger).foreground
                              : toneOf(context, PillTone.success).foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_payment == 'qris') ...[
                if (qrisPayload != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'QRIS dinamis',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          formatRupiah(totals.total),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: PosColors.skyDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        QrImageView(
                          data: qrisPayload,
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Minta pelanggan memindai QR ini. Dibuat offline dari QRIS statis warung.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: toneOf(context, PillTone.warning).background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'QRIS belum diatur. Masukkan string QRIS statis warung di '
                      'Pengaturan → Pembayaran. Untuk sekarang, transaksi dicatat '
                      'setelah kasir menekan selesai (mode simulasi).',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: toneOf(context, PillTone.warning).foreground,
                      ),
                    ),
                  ),
              ] else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: toneOf(context, PillTone.info).background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _payment == 'transfer'
                        ? 'Pastikan transfer sudah diterima sebelum menyelesaikan transaksi.'
                        : 'Pastikan pembayaran kartu sudah diterima sebelum menyelesaikan transaksi.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: toneOf(context, PillTone.info).foreground,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : () => _submit(controller),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 19),
                label: Text(
                  _busy
                      ? 'Menyimpan…'
                      : _payment == 'qris' && qrisPayload == null
                          ? 'Simulasikan QRIS dibayar'
                          : 'Selesaikan transaksi',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<int> _quickAmounts(int total) {
    final values = <int>{total};
    for (final candidate in const [10000, 20000, 50000, 100000, 150000, 200000]) {
      if (candidate >= total) values.add(candidate);
    }
    final rounded = ((total + 4999) ~/ 5000) * 5000;
    if (rounded > total) values.add(rounded);
    final list = values.toList()..sort();
    return list.take(6).toList();
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool active;
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
          color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: active ? color : theme.dividerColor,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? color : theme.iconTheme.color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ==========================================================================
   STRUK
   ========================================================================== */

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final lines = ReceiptBuilder.forOrder(order, controller.settings);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: toneOf(context, PillTone.success).background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: toneOf(context, PillTone.success).foreground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transaksi berhasil',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${ReceiptBuilder.paymentLabel(order.payment)} · '
                          '${formatRupiah(order.total)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF071B27)
                        : const Color(0xFFFBFDFE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in lines)
                        if (line.divider)
                          const DashedDivider(height: 12)
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: Text(
                              line.text,
                              textAlign: switch (line.align) {
                                ReceiptAlign.center => TextAlign.center,
                                ReceiptAlign.right => TextAlign.right,
                                ReceiptAlign.left => TextAlign.left,
                              },
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: line.big ? 14 : 11.5,
                                height: 1.35,
                                fontWeight:
                                    line.bold ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                children: [
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
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => controller.printReceipt(order),
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: const Text('Cetak struk'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Transaksi baru'),
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
