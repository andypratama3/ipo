import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/// Warna aksen status yang konsisten di terang & gelap.
class ToneColors {
  const ToneColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

ToneColors toneOf(BuildContext context, PillTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (tone) {
    case PillTone.success:
      return ToneColors(
        dark ? const Color(0xFF0F3A2B) : const Color(0xFFE6F8EF),
        dark ? const Color(0xFF6FE3B0) : const Color(0xFF0B7A4C),
      );
    case PillTone.warning:
      return ToneColors(
        dark ? const Color(0xFF3D2E0A) : const Color(0xFFFFF6E0),
        dark ? const Color(0xFFF7C65A) : const Color(0xFF9A6400),
      );
    case PillTone.danger:
      return ToneColors(
        dark ? const Color(0xFF3D1620) : const Color(0xFFFFEDEF),
        dark ? const Color(0xFFF79AA5) : const Color(0xFFB32636),
      );
    case PillTone.info:
      return ToneColors(
        dark ? const Color(0xFF0C3247) : const Color(0xFFE7F5FE),
        dark ? const Color(0xFF7CCBF5) : const Color(0xFF0A6C9E),
      );
    case PillTone.neutral:
      return ToneColors(
        dark ? const Color(0xFF1B3A4D) : const Color(0xFFF1F5F9),
        dark ? const Color(0xFFB7D2E2) : const Color(0xFF48627A),
      );
  }
}

enum PillTone { neutral, success, warning, danger, info }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
    this.radius = 999,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;

  /// 999 = bentuk pil penuh. Isi nilai kecil (mis. 8) untuk bentuk kotak.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = toneOf(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: colors.foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    this.kicker,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String? kicker;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (kicker != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  kicker!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: PosColors.sky,
                  ),
                ),
              ),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ),
          ],
        );
        if (actions.isEmpty) return heading;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
      },
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.kicker,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? kicker;
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || trailing != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (kicker != null)
                          Text(
                            kicker!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        if (title != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              title!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon = Icons.insights_rounded,
    this.primary = false,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = primary ? Colors.white : theme.colorScheme.onSurface;
    final muted = primary
        ? Colors.white.withValues(alpha: 0.78)
        : theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: primary
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PosColors.skyDark, PosColors.sky],
              )
            : null,
        color: primary ? null : theme.cardTheme.color,
        border: primary
            ? null
            : Border.all(color: theme.dividerColor.withValues(alpha: 0.9)),
        boxShadow: primary
            ? [
                BoxShadow(
                  color: PosColors.sky.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.18)
                      : theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: primary ? Colors.white : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: foreground,
              ),
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint!,
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
              ),
            ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: style.copyWith(
                color: bold
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style.copyWith(
                color: valueColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.height = 18});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const dash = 5.0;
            final count = (constraints.maxWidth / (dash * 2)).floor();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                count,
                (_) => Container(
                  width: dash,
                  height: 1,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.emoji,
    required this.name,
    required this.price,
    this.stockLabel,
    this.available = true,
    this.onTap,
  });

  final String emoji;
  final String name;
  final int price;
  final String? stockLabel;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: available ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                  const Spacer(),
                  if (stockLabel != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        stockLabel!,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 6),
              Text(
                formatRupiah(price),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kotak isian dengan label di atas — dipakai di semua formulir.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              hint!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
      ],
    );
  }
}

void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Lembar bawah dengan lebar terbatas supaya di tablet tidak melebar penuh
/// seperti di web `pos.css` (panel keranjang selebar 370px).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  double maxWidth = 560,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    useSafeArea: true,
    constraints: BoxConstraints(maxWidth: maxWidth),
    builder: builder,
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya, lanjutkan',
  String cancelLabel = 'Batal',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: PosColors.red)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
