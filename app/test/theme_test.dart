import 'dart:math' as math;

import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const t = CortaTokens.dark;

  test('cores base batem com a decisão do PO', () {
    expect(t.bg, const Color(0xFF000000));
    expect(t.surface, const Color(0xFF1C1C1E));
    expect(t.surface2, const Color(0xFF2C2C2E));
    expect(t.text, const Color(0xFFFFFFFF));
    expect(t.textMuted, const Color(0xFF8E8E93));
    expect(t.textMutedOnSurface2, const Color(0xFFAEAEB2));
    expect(t.accent, const Color(0xFFE6B325));
    expect(t.onAccent, const Color(0xFF000000));
  });

  group('contraste AA (4,5:1)', () {
    final pares = <String, (Color, Color)>{
      'texto no fundo': (t.text, t.bg),
      'secundário no fundo': (t.textMuted, t.bg),
      'secundário no card': (t.textMuted, t.surface),
      'secundário no card elevado': (t.textMutedOnSurface2, t.surface2),
      'preto no botão amarelo': (t.onAccent, t.accent),
      'amarelo no fundo': (t.accent, t.bg),
      'amarelo no card': (t.accent, t.surface),
      'aba inativa no fundo': (t.navInactive, t.bg),
      'placeholder no campo': (t.inputPlaceholder, t.surface),
    };
    pares.forEach((nome, par) {
      test(nome, () {
        expect(contrast(par.$1, par.$2), greaterThanOrEqualTo(4.5));
      });
    });
  });

  test('botão principal é o amarelo com texto preto', () {
    final theme = buildCortaTheme();
    final style = theme.filledButtonTheme.style!;
    expect(style.backgroundColor!.resolve({}), t.accent);
    expect(style.foregroundColor!.resolve({}), t.onAccent);
  });

  test('títulos em Inter 800', () {
    final theme = buildCortaTheme();
    expect(theme.textTheme.headlineLarge!.fontWeight, FontWeight.w800);
    expect(theme.textTheme.headlineLarge!.fontFamily, kCortaFontFamily);
  });

  test('chip ativo não usa o amarelo', () {
    final theme = buildCortaTheme();
    expect(theme.chipTheme.selectedColor, isNot(t.accent));
  });

  test('#636366 saiu do tema', () {
    const proibida = Color(0xFF636366);
    expect(t.navInactive, isNot(proibida));
    expect(t.inputPlaceholder, isNot(proibida));
    expect(t.navInactive, const Color(0xFF8E8E93));
    expect(t.inputPlaceholder, const Color(0xFF8E8E93));
  });
}
