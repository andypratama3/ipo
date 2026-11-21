import 'package:material_ui/material_ui.dart';

/// Token warna yang sama dengan `pos.css` supaya tampilan web dan Flutter seragam.
class PosColors {
  static const ink = Color(0xFF0C4A6E);
  static const body = Color(0xFF1E3A5F);
  static const muted = Color(0xFF6B849D);
  static const line = Color(0xFFDBEAF3);
  static const soft = Color(0xFFF5FAFD);
  static const sky = Color(0xFF0EA5E9);
  static const skyDark = Color(0xFF0369A1);
  static const green = Color(0xFF16A36A);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFE45B68);
  static const sidebar = Color(0xFF082F49);
  static const sidebarMuted = Color(0xFF9FC1D7);
  static const white = Colors.white;
}

class PosColorsDark {
  static const ink = Color(0xFFE0F2FE);
  static const body = Color(0xFFD7E8F3);
  static const muted = Color(0xFF91AFC3);
  static const line = Color(0xFF24475D);
  static const soft = Color(0xFF081E2C);
  static const surface = Color(0xFF0D2B3D);
  static const sidebar = Color(0xFF041824);
}

class PosTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        surface: Colors.white,
        background: PosColors.soft,
        ink: PosColors.ink,
        body: PosColors.body,
        muted: PosColors.muted,
        line: PosColors.line,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        surface: PosColorsDark.surface,
        background: PosColorsDark.soft,
        ink: PosColorsDark.ink,
        body: PosColorsDark.body,
        muted: PosColorsDark.muted,
        line: PosColorsDark.line,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color background,
    required Color ink,
    required Color body,
    required Color muted,
    required Color line,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: PosColors.sky,
      brightness: brightness,
      primary: PosColors.sky,
      surface: surface,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: body, displayColor: ink),
      dividerColor: line,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? PosColorsDark.soft
            : const Color(0xFFF8FBFD),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: PosColors.sky, width: 1.5),
        ),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PosColors.sky,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PosColors.skyDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
  }
}
