import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
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
      expect(find.textContaining('DATA_SOURCE'), findsWidgets);
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
