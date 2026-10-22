import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/theme/corta_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CT-00-49: DATA_SOURCE inválido mostra tela de erro legível, nunca tela branca nem mock.
void main() {
  AppConfig withSource(Flavor flavor, String raw) => AppConfig(
    flavor: flavor,
    dataSource: AppConfig.parseDataSource(raw),
    apiBaseUrl: 'http://localhost',
  );

  // O botão "Entrar como cliente novo" do Menu do app Cliente (menu_screen.dart).
  const newClientButton = ValueKey('menu-new-client');

  /// Sobe o app Cliente pelo mesmo caminho do APK ([rootFor]) e abre o Menu.
  Future<void> openClienteMenu(WidgetTester tester, String raw) async {
    SharedPreferences.setMockInitialValues({DeviceStore.kIntroSeen: true});
    tester.view.physicalSize = const Size(2400, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      rootFor(Flavor.cliente, () => withSource(Flavor.cliente, raw)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu').last);
    await tester.pumpAndSettle();
  }

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
      expect(find.byKey(newClientButton), findsNothing);
      expect(find.text('Entrar como cliente novo'), findsNothing);
      expect(find.byType(CortaAquiApp), findsNothing);
    });
  }

  testWidgets('DATA_SOURCE válido abre o app normal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      rootFor(Flavor.casa, () => withSource(Flavor.casa, 'mock')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CortaAquiApp), findsOneWidget);
    expect(find.text('Erro de configuração'), findsNothing);
  });

  testWidgets(
    'DATA_SOURCE=mock: o Menu do app Cliente tem o "Entrar como cliente novo"',
    (tester) async {
      await openClienteMenu(tester, 'mock');

      expect(find.text('Erro de configuração'), findsNothing);
      expect(find.byKey(newClientButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(newClientButton),
          matching: find.text('Entrar como cliente novo'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'DATA_SOURCE=api: o Menu do app Cliente não tem o "Entrar como cliente novo"',
    (tester) async {
      await openClienteMenu(tester, 'api');

      expect(find.text('Erro de configuração'), findsNothing);
      expect(find.textContaining('Modo API'), findsOneWidget);
      expect(find.byKey(newClientButton), findsNothing);
      expect(find.text('Entrar como cliente novo'), findsNothing);
    },
  );
}
