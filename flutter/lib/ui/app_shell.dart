import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_controller.dart';
import 'cashier_screen.dart';
import 'dashboard_screen.dart';
import 'menu_screen.dart';
import 'queues_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'widgets/common.dart';

/// Rangka aplikasi: AppBar + navigasi bawah, sederhana dan rapi untuk HP/tablet.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _navigateIndex(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  Future<void> _logout(AppController controller) async {
    final ok = await confirmDialog(
      context,
      title: 'Keluar dari aplikasi?',
      message:
          'Keranjang yang sedang berjalan tetap tersimpan untuk kasir berikutnya.',
      confirmLabel: 'Keluar',
    );
    if (ok) await controller.logout();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Pengaturan')),
          body: const SettingsScreen(showHeading: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final owner = controller.isOwner;

    final items = <_NavItem>[
      const _NavItem('Beranda', Icons.home_rounded),
      const _NavItem('Kasir', Icons.point_of_sale_rounded),
      const _NavItem('Pesanan', Icons.receipt_long_rounded),
      if (owner) const _NavItem('Menu', Icons.restaurant_menu_rounded),
      const _NavItem('Laporan', Icons.bar_chart_rounded),
    ];
    final index = _index.clamp(0, items.length - 1);

    final pages = <Widget>[
      DashboardScreen(onNavigate: _navigateIndex),
      const CashierScreen(),
      QueuesScreen(onOpenCashier: () => _navigateIndex(1)),
      if (owner) const MenuScreen(),
      const ReportsScreen(),
    ];

    final pending = controller.pendingOrders.length;
    final online = controller.onlineOrders.length;
    final queueBadge = pending + online;

    final status = controller.syncStatus;
    final showBanner = status != null &&
        controller.isConfigured &&
        (status.error.isNotEmpty || status.queued > 0);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        shape: Border(bottom: BorderSide(color: theme.dividerColor)),
        title: Row(
          children: [
            _BrandMark(theme: theme),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.settings.businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    '${controller.user?.name ?? 'Kasir'} · ${controller.user?.role ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _SyncChip(
            label: controller.syncStatus?.label ?? 'Lokal',
            tone: _syncTone(controller),
            onTap: controller.manualSync,
          ),
          IconButton(
            tooltip: controller.theme == 'dark' ? 'Mode terang' : 'Mode gelap',
            onPressed: controller.toggleTheme,
            icon: Icon(
              controller.theme == 'dark'
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 21,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu akun',
            onSelected: (value) {
              if (value == 'settings') _openSettings();
              if (value == 'logout') _logout(controller);
            },
            itemBuilder: (context) => [
              if (owner)
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined, size: 20),
                    title: Text('Pengaturan'),
                  ),
                ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded, size: 20),
                  title: Text('Keluar'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (showBanner) _StatusBanner(controller: controller),
            Expanded(
              child: IndexedStack(index: index, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: theme.cardTheme.color,
          indicatorColor: PosColors.sky.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 10.5,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? PosColors.skyDark
                  : theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected)
                  ? PosColors.skyDark
                  : theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _navigateIndex,
          height: 66,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (var i = 0; i < items.length; i++)
              NavigationDestination(
                icon: _navIcon(
                  Icon(items[i].icon),
                  items[i].label == 'Pesanan' ? queueBadge : 0,
                ),
                selectedIcon: _navIcon(
                  Icon(items[i].icon),
                  items[i].label == 'Pesanan' ? queueBadge : 0,
                ),
                label: items[i].label,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

PillTone _syncTone(AppController controller) {
  final status = controller.syncStatus;
  if (!controller.isConfigured) return PillTone.neutral;
  if (status?.error.isNotEmpty ?? false) return PillTone.danger;
  if ((status?.queued ?? 0) > 0) return PillTone.warning;
  return PillTone.success;
}

Widget _navIcon(Widget icon, int count) {
  if (count <= 0) return icon;
  return Badge(
    label: Text('$count'),
    backgroundColor: PosColors.orange,
    child: icon,
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.syncStatus!;
    final tone = status.error.isNotEmpty ? PillTone.danger : PillTone.warning;
    final colors = toneOf(context, tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: colors.background,
      child: Row(
        children: [
          Icon(
            status.error.isNotEmpty
                ? Icons.cloud_off_rounded
                : Icons.cloud_upload_rounded,
            size: 15,
            color: colors.foreground,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              status.error.isNotEmpty
                  ? 'Sinkronisasi gagal — perubahan tetap tersimpan di perangkat.'
                  : '${status.queued} perubahan menunggu dikirim ke server.',
              style: TextStyle(fontSize: 11.5, color: colors.foreground),
            ),
          ),
          TextButton(
            onPressed: controller.manualSync,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Sinkron'),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Image.asset(
        'assets/img/pangsitmie.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => const Icon(
          Icons.ramen_dining_rounded,
          size: 20,
          color: PosColors.sky,
        ),
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final PillTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = toneOf(context, tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.foreground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
