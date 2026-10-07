import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual overrides used only while easy read mode is on.
abstract final class EasyReadTheme {
  static const double textScale = 1.35;
  static const Color lightForeground = Color(0xFF111111);
  static const Color lightAccent = Color(0xFFE65100);
  static const Color darkAccent = Color(0xFFFFE082);

  static TextScaler undoTextScale(TextScaler scaled) {
    final factor = scaled.scale(1) / textScale;
    return TextScaler.linear(factor <= 0 ? 1 : factor);
  }

  static double _saturation(Color color) {
    final r = color.r;
    final g = color.g;
    final b = color.b;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    if (max == 0) return 0;
    return (max - min) / max;
  }

  /// Grey, faded black, and faded white are hard to read.
  /// Saturated colours such as amber are left as they are.
  static bool isLowContrast(Color color) {
    if (_saturation(color) > 0.22) return false;
    if (color.a < 0.82) return true;
    final lum = color.computeLuminance();
    return lum > 0.22 && lum < 0.78;
  }

  static Color lift(Color color, Brightness brightness) {
    if (!isLowContrast(color)) return color;
    return brightness == Brightness.dark ? Colors.white : lightForeground;
  }

  static Color foreground(Brightness brightness) =>
      brightness == Brightness.dark ? Colors.white : lightForeground;

  static Color accent(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;

  static ThemeData apply(ThemeData base) {
    final isDark = base.brightness == Brightness.dark;
    final fg = foreground(base.brightness);
    final strong = accent(base.brightness);
    final buttonText = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final buttonMin = const Size(72, 56);

    TextStyle? bold(TextStyle? style) => style?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        );

    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: isDark ? Colors.black : Colors.white,
      hintColor: fg,
      disabledColor: fg,
      dividerColor: fg,
      iconTheme: IconThemeData(color: fg, size: 28),
      primaryIconTheme: IconThemeData(color: fg, size: 28),
      colorScheme: base.colorScheme.copyWith(
        primary: strong,
        onPrimary: Colors.black,
        secondary: strong,
        onSecondary: Colors.black,
        surface: isDark ? Colors.black : Colors.white,
        onSurface: fg,
        onSurfaceVariant: fg,
        outline: fg,
      ),
      textTheme: text.copyWith(
        bodyLarge: bold(text.bodyLarge),
        bodyMedium: bold(text.bodyMedium),
        bodySmall: bold(text.bodySmall),
        titleLarge: bold(text.titleLarge),
        titleMedium: bold(text.titleMedium),
        titleSmall: bold(text.titleSmall),
        labelLarge: bold(text.labelLarge),
        labelMedium: bold(text.labelMedium),
        labelSmall: bold(text.labelSmall),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 72,
        minVerticalPadding: 12,
        iconColor: fg,
        textColor: fg,
        titleTextStyle: TextStyle(
          color: fg,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
        subtitleTextStyle: TextStyle(
          color: fg,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: strong,
          minimumSize: buttonMin,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: buttonText,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: strong,
          foregroundColor: Colors.black,
          minimumSize: buttonMin,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: buttonText,
          shape: buttonShape,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: strong,
          foregroundColor: Colors.black,
          minimumSize: buttonMin,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: buttonText,
          shape: buttonShape,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: buttonMin,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: buttonText,
          side: BorderSide(color: fg, width: 2),
          shape: buttonShape,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size(56, 56),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
        titleTextStyle: TextStyle(
          color: fg,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
        contentTextStyle: TextStyle(
          color: fg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}
