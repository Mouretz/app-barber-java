import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final flavor in Flavor.values) {
    testWidgets('${flavor.name} abre com o tema e a aba ativa amarela', (
      tester,
    ) async {
      final config = AppConfig(
        flavor: flavor,
        dataSource: DataSource.mock,
        apiBaseUrl: 'http://localhost',
      );
      await tester.pumpWidget(CortaAquiApp(config: config));

      expect(find.text(flavor.appName), findsOneWidget);
      expect(find.text('Modo mock: roda sem servidor.'), findsOneWidget);

      final firstLabel = flavor == Flavor.cliente ? 'Início' : 'Agenda';
      final label = tester.widget<Text>(find.text(firstLabel));
      expect(label.style!.color, CortaTokens.dark.accent);
    });
  }
}
