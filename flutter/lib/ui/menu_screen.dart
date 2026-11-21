import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/defaults.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final query = _search.text.trim().toLowerCase();
    final products = controller.products.where((product) {
      final haystack = '${product.name} ${product.category}'.toLowerCase();
      if (query.isNotEmpty && !haystack.contains(query)) return false;
      final status = controller.availability(product, ignoreCart: true).status;
      switch (controller.menuFilter) {
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

    var available = 0;
    var low = 0;
    var unavailable = 0;
    for (final product in controller.products) {
      final status = controller.availability(product, ignoreCart: true).status;
      if (status == 'available') {
        available += 1;
      } else if (status == 'pending') {
        low += 1;
      } else {
        unavailable += 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        PageHeading(
          kicker: 'Katalog',
          title: 'Menu warung',
          subtitle: 'Kelola harga, kategori, stok, dan status tersedia menu.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (context) => const _CategorySheet(),
              ),
              icon: const Icon(Icons.category_outlined, size: 18),
              label: const Text('Edit kategori'),
            ),
            FilledButton.icon(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (context) => const _ProductSheet(),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah menu'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : 2;
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
                    label: 'Menu terdaftar',
                    value: formatNumber(controller.products.length),
                    hint: 'total katalog',
                    icon: Icons.menu_book_rounded,
                    primary: true,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Tersedia',
                    value: formatNumber(available),
                    hint: 'siap dijual',
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Stok menipis',
                    value: formatNumber(low),
                    hint: '≤ 3 porsi',
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatCard(
                    label: 'Nonaktif / habis',
                    value: formatNumber(unavailable),
                    hint: 'tidak tampil di kasir',
                    icon: Icons.block_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        SectionCard(
          kicker: 'Daftar menu',
          title: '${formatNumber(products.length)} menu ditampilkan',
          trailing: IconButton(
            tooltip: 'Muat ulang dari server',
            onPressed: () => controller.manualSync(),
            icon: const Icon(Icons.sync_rounded, size: 20),
          ),
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Cari nama menu…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in const [
                      ('all', 'Semua'),
                      ('available', 'Tersedia'),
                      ('low', 'Stok menipis'),
                      ('unavailable', 'Nonaktif'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: controller.menuFilter == filter.$1,
                          onSelected: (_) => controller.setMenuFilter(filter.$1),
                          label: Text(filter.$2),
                          showCheckmark: false,
                          selectedColor: PosColors.sky,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: controller.menuFilter == filter.$1
                                ? Colors.white
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (products.isEmpty)
                const EmptyState(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Tidak ada menu',
                  message: 'Ubah filter atau tambah menu baru ke katalog.',
                )
              else
                for (final product in products)
                  _MenuRow(product: product),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Menu yang dinonaktifkan atau stoknya habis tidak muncul di layar '
                  'kasir. Perubahan katalog disinkronkan ke perangkat lain oleh akun pemilik.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final availability = controller.availability(product, ignoreCart: true);
    final tone = switch (availability.status) {
      'available' => PillTone.success,
      'pending' => PillTone.warning,
      _ => PillTone.danger,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(product.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatRupiah(product.price),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      controller.categoryLabel(product.category),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    StatusPill(
                      label: product.stock == null
                          ? availability.label
                          : '${availability.label} · ${product.stock}',
                      tone: tone,
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Aksi menu',
            onSelected: (value) async {
              switch (value) {
                case 'edit':
                  await showAppSheet<void>(
                    context,
                    builder: (context) => _ProductSheet(product: product),
                  );
                  break;
                case 'toggle':
                  await controller.toggleProductAvailability(product.id);
                  break;
                case 'delete':
                  final ok = await confirmDialog(
                    context,
                    title: 'Hapus menu?',
                    message:
                        '${product.name} dihapus dari katalog dan keranjang aktif.',
                    confirmLabel: 'Hapus',
                    danger: true,
                  );
                  if (ok) await controller.deleteProduct(product.id);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 19),
                  title: Text('Ubah menu'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    product.available
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                  ),
                  title: Text(product.available ? 'Nonaktifkan' : 'Aktifkan'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded,
                      size: 19, color: PosColors.red),
                  title: Text('Hapus menu',
                      style: TextStyle(color: PosColors.red)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ==========================================================================
   FORM MENU
   ========================================================================== */

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({this.product});

  final Product? product;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _description;
  late String _category;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    final controller = context.read<AppController>();
    _name = TextEditingController(text: product?.name ?? '');
    _price = TextEditingController(
      text: product == null ? '' : '${product.price}',
    );
    _stock = TextEditingController(
      text: product?.stock == null ? '' : '${product!.stock}',
    );
    _description = TextEditingController(text: product?.description ?? '');
    _category = product?.category ??
        (controller.categories.isNotEmpty
            ? controller.categories.first.id
            : 'lainnya');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final controller = context.read<AppController>();
    setState(() => _busy = true);
    final error = await controller.saveProduct(
      id: widget.product?.id,
      name: _name.text,
      categoryId: _category,
      price: int.tryParse(_price.text) ?? 0,
      stock: _stock.text.trim().isEmpty ? null : int.tryParse(_stock.text),
      description: _description.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      showAppSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final editing = widget.product != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? 'Ubah menu' : 'Tambah menu',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                editing
                    ? 'Perubahan langsung tersinkron ke perangkat lain.'
                    : 'Menu baru langsung tampil di layar kasir.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Nama menu',
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'mis. Mie Pangsit Original'),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Kategori',
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  items: controller.categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text('${category.emoji}  ${category.label}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _category = value ?? _category),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LabeledField(
                      label: 'Harga (Rp)',
                      child: TextField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(hintText: '20000'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LabeledField(
                      label: 'Stok (opsional)',
                      hint: 'Kosong = tanpa batas stok.',
                      child: TextField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(hintText: '∞'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Deskripsi (opsional)',
                child: TextField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Deskripsi singkat untuk pelanggan',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 19),
                label: Text(_busy ? 'Menyimpan…' : 'Simpan menu'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ==========================================================================
   KATEGORI
   ========================================================================== */

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _label = TextEditingController();
  String _emoji = kCategoryEmojiChoices.first;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    final controller = context.read<AppController>();
    setState(() => _busy = true);
    final error = await controller.addCategory(_label.text, _emoji);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      _label.clear();
    } else {
      showAppSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kelola kategori',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Kategori tampil sebagai tab di layar kasir.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                shrinkWrap: true,
                children: [
                  for (final category in controller.categories)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () async {
                              final emoji = await _pickEmoji(context, category.emoji);
                              if (emoji != null) {
                                await controller.updateCategoryEmoji(category.id, emoji);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(category.emoji,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.label,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${controller.products.where((product) => product.category == category.id).length} menu',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Ganti nama',
                            onPressed: () => _rename(context, category),
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                          IconButton(
                            tooltip: 'Hapus kategori',
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Hapus kategori?',
                                message:
                                    'Kategori "${category.label}" hanya bisa dihapus bila tidak dipakai menu.',
                                confirmLabel: 'Hapus',
                                danger: true,
                              );
                              if (ok) await controller.deleteCategory(category.id);
                            },
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 19, color: PosColors.red),
                          ),
                        ],
                      ),
                    ),
                  const DashedDivider(),
                  Text(
                    'Kategori baru',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () async {
                          final emoji = await _pickEmoji(context, _emoji);
                          if (emoji != null) setState(() => _emoji = emoji);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Text(_emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _label,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Nama kategori baru',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _busy ? null : _add,
                          child: const Text('Tambah'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ketuk kotak emoji untuk memilih ikon kategori.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
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

  Future<void> _rename(BuildContext context, Category category) async {
    final controller = context.read<AppController>();
    final input = TextEditingController(text: category.label);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ganti nama kategori'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: 'Nama kategori'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null) {
      await controller.renameCategory(category.id, value);
    }
  }
}

Future<String?> _pickEmoji(BuildContext context, String current) {
  return showAppSheet<String>(
    context,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih emoji kategori',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final emoji in [kEmojiAutoIcon, ...kCategoryEmojiChoices])
                    InkWell(
                      onTap: () => Navigator.of(context).pop(
                        emoji == kEmojiAutoIcon ? '' : emoji,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: emoji == current
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                          ),
                          color: emoji == current
                              ? theme.colorScheme.primary.withValues(alpha: 0.08)
                              : null,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Ikon $kEmojiAutoIcon memilih emoji otomatis sesuai nama kategori.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
