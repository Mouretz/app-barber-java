import 'package:flutter/material.dart';

/// Cores do CortaAqui. Base do `nadaaqui-mobile` (tema escuro OLED) com o
/// amarelo da marca no lugar do verde-água.
///
/// Regra do amarelo ([CortaTokens.accent]): só em indicador ativo (aba ativa,
/// ponto ativo da introdução), no profissional escolhido e no botão principal.
/// Em qualquer outro lugar use branco ou cinza.
@immutable
class CortaTokens extends ThemeExtension<CortaTokens> {
  const CortaTokens({
    required this.bg,
    required this.bgElevated,
    required this.surface,
    required this.surface2,
    required this.text,
    required this.textMuted,
    required this.textMutedOnSurface2,
    required this.accent,
    required this.onAccent,
    required this.navInactive,
    required this.hairline,
    required this.border,
    required this.chipInactiveBg,
    required this.chipInactiveFg,
    required this.inputPlaceholder,
    required this.sheetHandle,
    required this.error,
    required this.errorBg,
    required this.slotFree,
    required this.slotOffHours,
    required this.slotBlocked,
    required this.statusScheduled,
    required this.statusCompleted,
    required this.statusNoShow,
    required this.statusCanceled,
  });

  final Color bg;
  final Color bgElevated;

  /// Card padrão. [textMuted] passa no contraste AA aqui.
  final Color surface;

  /// Card elevado / chip. Aqui o texto secundário é [textMutedOnSurface2].
  final Color surface2;
  final Color text;

  /// Texto secundário sobre [bg] e [surface].
  final Color textMuted;

  /// Texto secundário sobre [surface2] (`#8E8E93` reprova AA ali).
  final Color textMutedOnSurface2;

  /// Amarelo da marca. Ver a regra no topo da classe.
  final Color accent;

  /// Texto e ícone em cima do [accent] (botão principal).
  final Color onAccent;
  final Color navInactive;

  /// Linha fina do menu e divisórias.
  final Color hairline;
  final Color border;
  final Color chipInactiveBg;
  final Color chipInactiveFg;
  final Color inputPlaceholder;
  final Color sheetHandle;
  final Color error;
  final Color errorBg;

  // Agenda da Casa (história 2).
  final Color slotFree;

  /// Fora do expediente: cinza.
  final Color slotOffHours;
  final Color slotBlocked;

  // Status do agendamento.
  final Color statusScheduled;
  final Color statusCompleted;
  final Color statusNoShow;
  final Color statusCanceled;

  static const dark = CortaTokens(
    bg: Color(0xFF000000),
    bgElevated: Color(0xFF0A0A0A),
    surface: Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF8E8E93),
    textMutedOnSurface2: Color(0xFFAEAEB2),
    accent: Color(0xFFE6B325),
    onAccent: Color(0xFF000000),
    navInactive: Color(0xFF8E8E93),
    hairline: Color(0xFF1C1C1E),
    border: Color(0xFF2C2C2E),
    chipInactiveBg: Color(0xFF2C2C2E),
    chipInactiveFg: Color(0xFFFFFFFF),
    inputPlaceholder: Color(0xFF8E8E93),
    sheetHandle: Color(0xFF3A3A3C),
    error: Color(0xFFFF453A),
    errorBg: Color(0xFF3B1210),
    slotFree: Color(0xFF1C1C1E),
    slotOffHours: Color(0xFF0A0A0A),
    slotBlocked: Color(0xFF3A3A3C),
    statusScheduled: Color(0xFFFFFFFF),
    statusCompleted: Color(0xFF4ADE80),
    statusNoShow: Color(0xFFFF9F0A),
    statusCanceled: Color(0xFF8E8E93),
  );

  static CortaTokens of(BuildContext context) {
    return Theme.of(context).extension<CortaTokens>() ?? CortaTokens.dark;
  }

  @override
  CortaTokens copyWith({
    Color? bg,
    Color? bgElevated,
    Color? surface,
    Color? surface2,
    Color? text,
    Color? textMuted,
    Color? textMutedOnSurface2,
    Color? accent,
    Color? onAccent,
    Color? navInactive,
    Color? hairline,
    Color? border,
    Color? chipInactiveBg,
    Color? chipInactiveFg,
    Color? inputPlaceholder,
    Color? sheetHandle,
    Color? error,
    Color? errorBg,
    Color? slotFree,
    Color? slotOffHours,
    Color? slotBlocked,
    Color? statusScheduled,
    Color? statusCompleted,
    Color? statusNoShow,
    Color? statusCanceled,
  }) {
    return CortaTokens(
      bg: bg ?? this.bg,
      bgElevated: bgElevated ?? this.bgElevated,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textMutedOnSurface2: textMutedOnSurface2 ?? this.textMutedOnSurface2,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      navInactive: navInactive ?? this.navInactive,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      chipInactiveBg: chipInactiveBg ?? this.chipInactiveBg,
      chipInactiveFg: chipInactiveFg ?? this.chipInactiveFg,
      inputPlaceholder: inputPlaceholder ?? this.inputPlaceholder,
      sheetHandle: sheetHandle ?? this.sheetHandle,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      slotFree: slotFree ?? this.slotFree,
      slotOffHours: slotOffHours ?? this.slotOffHours,
      slotBlocked: slotBlocked ?? this.slotBlocked,
      statusScheduled: statusScheduled ?? this.statusScheduled,
      statusCompleted: statusCompleted ?? this.statusCompleted,
      statusNoShow: statusNoShow ?? this.statusNoShow,
      statusCanceled: statusCanceled ?? this.statusCanceled,
    );
  }

  @override
  CortaTokens lerp(ThemeExtension<CortaTokens>? other, double t) {
    if (other is! CortaTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CortaTokens(
      bg: l(bg, other.bg),
      bgElevated: l(bgElevated, other.bgElevated),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textMutedOnSurface2: l(textMutedOnSurface2, other.textMutedOnSurface2),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      navInactive: l(navInactive, other.navInactive),
      hairline: l(hairline, other.hairline),
      border: l(border, other.border),
      chipInactiveBg: l(chipInactiveBg, other.chipInactiveBg),
      chipInactiveFg: l(chipInactiveFg, other.chipInactiveFg),
      inputPlaceholder: l(inputPlaceholder, other.inputPlaceholder),
      sheetHandle: l(sheetHandle, other.sheetHandle),
      error: l(error, other.error),
      errorBg: l(errorBg, other.errorBg),
      slotFree: l(slotFree, other.slotFree),
      slotOffHours: l(slotOffHours, other.slotOffHours),
      slotBlocked: l(slotBlocked, other.slotBlocked),
      statusScheduled: l(statusScheduled, other.statusScheduled),
      statusCompleted: l(statusCompleted, other.statusCompleted),
      statusNoShow: l(statusNoShow, other.statusNoShow),
      statusCanceled: l(statusCanceled, other.statusCanceled),
    );
  }
}
