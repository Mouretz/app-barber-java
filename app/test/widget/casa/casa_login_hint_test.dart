import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/presentation/casa/screens/login_screen.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resposta 1 do PO: a senha do mock aparece na tela de login só no build
/// mock, nunca no build api.
void main() {
  Future<void> pumpLogin(WidgetTester tester, DataSource source) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final config = AppConfig(
      flavor: Flavor.casa,
      dataSource: source,
      apiBaseUrl: 'http://localhost',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildCortaTheme(),
          home: LoginScreen(config: config),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool anyTextContains(String s) => find
      .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(s))
      .evaluate()
      .isNotEmpty;

  testWidgets('build mock mostra os 3 logins com o papel certo e a senha', (
    tester,
  ) async {
    await pumpLogin(tester, DataSource.mock);
    expect(find.text('Senha: ${MockCasaSeed.mockPassword}'), findsOneWidget);
    expect(
      find.text('Gerente (não atende): ${MockCasaSeed.marinaEmail}'),
      findsOneWidget,
    );
    expect(
      find.text('Gerente e profissional: ${MockCasaSeed.caioEmail}'),
      findsOneWidget,
    );
    expect(
      find.text('Profissional: ${MockCasaSeed.helenaEmail}'),
      findsOneWidget,
    );
  });

  testWidgets('build api não mostra senha nem e-mails do mock', (tester) async {
    await pumpLogin(tester, DataSource.api);
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    expect(anyTextContains(MockCasaSeed.mockPassword), isFalse);
    expect(anyTextContains('navalha.mock'), isFalse);
    expect(anyTextContains('Modo mock'), isFalse);
  });
}
