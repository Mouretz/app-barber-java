import 'package:flutter/material.dart';

import 'corta_tokens.dart';

/// Família de fonte empacotada em `assets/fonts` (Inter 400 a 800).
const String kCortaFontFamily = 'Inter';

/// Tema único do CortaAqui (escuro OLED), usado pelos dois apps.
ThemeData buildCortaTheme() {
  const t = CortaTokens.dark;
  final scheme = const ColorScheme.dark().copyWith(
    surface: t.bg,
    onSurface: t.text,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.text,
    onSecondary: t.bg,
    error: t.error,
    onError: t.text,
    outline: t.border,
    outlineVariant: t.hairline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: kCortaFontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    splashFactory: InkSparkle.splashFactory,
    extensions: const [t],
    textTheme: cortaTextTheme(t),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kCortaFontFamily,
        color: t.text,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // Botão principal: o único botão amarelo.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        disabledBackgroundColor: t.surface2,
        disabledForegroundColor: t.textMutedOnSurface2,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: kCortaFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        side: BorderSide(color: t.border),
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: kCortaFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.text,
        textStyle: const TextStyle(
          fontFamily: kCortaFontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    // Chip ativo é branco (não amarelo), igual ao NadaAqui.
    chipTheme: ChipThemeData(
      backgroundColor: t.chipInactiveBg,
      selectedColor: t.text,
      disabledColor: t.surface,
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontFamily: kCortaFontFamily,
        color: t.chipInactiveFg,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: kCortaFontFamily,
        color: t.bg,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.bg : t.text,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.text : t.surface2,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      dragHandleColor: t.sheetHandle,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface2,
      contentTextStyle: TextStyle(fontFamily: kCortaFontFamily, color: t.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      hintStyle: TextStyle(color: t.inputPlaceholder),
      labelStyle: TextStyle(color: t.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.text, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.error),
      ),
    ),
  );
}

/// Títulos em Inter 800 bem fechados, como no NadaAqui.
TextTheme cortaTextTheme(CortaTokens t) {
  return TextTheme(
    displaySmall: TextStyle(
      color: t.text,
      fontSize: 34,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.1,
    ),
    headlineLarge: TextStyle(
      color: t.text,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    ),
    headlineSmall: TextStyle(
      color: t.text,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
    titleLarge: TextStyle(
      color: t.text,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      color: t.text,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      color: t.text,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    bodyMedium: TextStyle(
      color: t.text,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: TextStyle(
      color: t.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      color: t.text,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: TextStyle(
      color: t.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}
