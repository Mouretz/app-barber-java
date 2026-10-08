import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/theme/corta_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CT-00-49: DATA_SOURCE inválido mostra tela de erro legível, nunca tela branca nem mock.
void main() {
  AppConfig withSource(Flavor flavor, String raw) => AppConfig(
    flavor: flavor,
    dataSource: AppConfig.parseDataSource(raw),
    apiBaseUrl: 'http://localhost',
  );

  for (final raw in ['prod', '']) {
    testWidgets('DATA_SOURCE="$raw" mostra a tela de erro de configuração', (
      tester,
    ) async {
      await tester.pumpWidget(
        rootFor(Flavor.cliente, () => withSource(Flavor.cliente, raw)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erro de configuração'), findsOneWidget);
      expect(
        find.textContaining('DATA_SOURCE recebido: "$raw"'),
        findsOneWidget,
      );

      // Contraste AA: título e detalhe com as cores do tema escuro, no fundo do tema.
      final title = tester.widget<Text>(find.text('Erro de configuração'));
      final detail = tester.widget<Text>(
        find.textContaining('DATA_SOURCE recebido'),
      );
      final bg = tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
      expect(title.style?.color, CortaTokens.dark.text);
      expect(detail.style?.color, CortaTokens.dark.textMuted);
      expect(bg, CortaTokens.dark.bg);
      expect(find.text('Entrar como cliente novo'), findsNothing);
      expect(find.byType(CortaAquiApp), findsNothing);
    });
  }

  testWidgets('DATA_SOURCE válido abre o app normal', (tester) async {
    await tester.pumpWidget(
      rootFor(Flavor.casa, () => withSource(Flavor.casa, 'mock')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CortaAquiApp), findsOneWidget);
    expect(find.text('Erro de configuração'), findsNothing);
  });
}
