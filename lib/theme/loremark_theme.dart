import 'package:flutter/material.dart';

/// Colors from the reading studio mockup: warm paper, brown ink, and an olive
/// accent.
abstract final class LoremarkColors {
  static const ink = Color(0xFF3B3029);
  static const muted = Color(0xFF908071);
  static const olive = Color(0xFF5B6047);
  static const onOlive = Color(0xFFFFF7E8);
  static const paper = Color(0xFFFFF8EF);
  static const header = Color(0xFFFFF9F0);
  static const line = Color(0xFFE8D9C5);
  static const gold = Color(0xFFBA8954);

  /// The reading boundary strip under the header.
  static const boundary = Color(0xFFEEE9DB);
  static const boundaryText = Color(0xFF7E795F);
  static const safeDot = Color(0xFF598E6F);

  /// Book text and chapter titles.
  static const readerText = Color(0xFF574638);
  static const readerTitle = Color(0xFF4D3A2B);

  /// The welcome-back card.
  static const welcomeStart = Color(0xFFF3E7D5);
  static const welcomeEnd = Color(0xFFF9EADD);
  static const welcomeBorder = Color(0xFFE5CCB0);
  static const welcomeTitle = Color(0xFF614634);
  static const welcomeText = Color(0xFF947C64);

  /// Tinted panels: chips, chapter controls, and reading-note quotes.
  static const panel = Color(0xFFF2E9D9);
  static const chip = Color(0xFFF5EBDC);
  static const chipBorder = Color(0xFFE5D4B8);
  static const chipText = Color(0xFFA0805C);
  static const noteQuote = Color(0xFFF6F0E4);
  static const noteBorder = Color(0xFFC09B68);

  static const navBar = Color(0xFFFFF6E9);
  static const navBorder = Color(0xFFE4D0B5);
  static const navIdle = Color(0xFFA6977E);
  static const navSelected = Color(0xFF6A6848);

  static const card = Color(0xFFFFFEFA);
  static const avatar = Color(0xFFEFDBC5);
  static const avatarText = Color(0xFF8F633D);
}

/// Serif face for headings and book text. Georgia ships on iOS; Android falls
/// back to its built-in serif.
const serifFamily = 'Georgia';
const serifFallback = ['serif', 'Times New Roman'];

TextStyle serif(double size, {Color? color, double? height}) => TextStyle(
  fontFamily: serifFamily,
  fontFamilyFallback: serifFallback,
  fontSize: size,
  height: height,
  color: color,
);

/// Small uppercase label, such as "CURRENTLY READING".
TextStyle kicker({Color color = LoremarkColors.gold, double size = 10}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
      color: color,
    );

ThemeData buildLoremarkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: LoremarkColors.olive,
        brightness: Brightness.light,
      ).copyWith(
        primary: LoremarkColors.olive,
        onPrimary: LoremarkColors.onOlive,
        secondary: LoremarkColors.gold,
        surface: LoremarkColors.paper,
        onSurface: LoremarkColors.ink,
        onSurfaceVariant: LoremarkColors.muted,
        outline: LoremarkColors.muted,
        outlineVariant: LoremarkColors.line,
        secondaryContainer: LoremarkColors.panel,
        onSecondaryContainer: LoremarkColors.ink,
        surfaceContainerHighest: LoremarkColors.panel,
      );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(9),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LoremarkColors.paper,
    dividerColor: LoremarkColors.line,
    textTheme: Typography.blackMountainView.apply(
      bodyColor: LoremarkColors.ink,
      displayColor: LoremarkColors.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: LoremarkColors.olive,
        foregroundColor: LoremarkColors.onOlive,
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: LoremarkColors.navSelected,
        shape: buttonShape,
      ),
    ),
    cardTheme: CardThemeData(
      color: LoremarkColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: LoremarkColors.line),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LoremarkColors.chip,
      side: const BorderSide(color: LoremarkColors.chipBorder),
      labelStyle: const TextStyle(fontSize: 12, color: LoremarkColors.chipText),
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: LoremarkColors.navBar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: LoremarkColors.panel,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? LoremarkColors.navSelected
              : LoremarkColors.navIdle,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? LoremarkColors.navSelected
              : LoremarkColors.navIdle,
        ),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: LoremarkColors.gold,
      thumbColor: LoremarkColors.olive,
      inactiveTrackColor: LoremarkColors.line,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: LoremarkColors.muted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LoremarkColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LoremarkColors.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LoremarkColors.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
