import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/presentation/casa/casa_app.dart';
import 'package:cortaaqui/presentation/casa/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'casa_harness.dart';

/// Decisão do PO: a Casa lembra o login (chave própria) até Sair ou 401.
void main() {
  const key = SessionNotifier.kSession;
  final login = find.byKey(const ValueKey('login-submit'));
  late FixedClock clock;
  late MockCasaRepository repo;

  setUp(() {
    clock = FixedClock(kCasaNow);
    repo = casaRepo(clock);
  });

  /// Reabre o app (novo ProviderScope) sem zerar o armazenamento.
  Future<void> reopen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(casaConfig),
          clockProvider.overrideWithValue(clock),
          casaRepositoryProvider.overrideWithValue(repo),
        ],
        child: const CasaApp(config: casaConfig),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String?> saved() async =>
      (await SharedPreferences.getInstance()).getString(key);

  testWidgets('chave da Casa é separada das do app Cliente', (tester) async {
    expect(key, 'cortaaqui.casa.session');
    expect(key.startsWith('cortaaqui.cliente.'), isFalse);
  });

  testWidgets('login fica guardado e o app reabre já logado', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    expect(login, findsNothing);
    expect(await saved(), isNotNull);
    await reopen(tester);
    expect(login, findsNothing);
    expect(find.text('Agenda'), findsWidgets);
  });

  testWidgets('Sair apaga o login guardado', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await openTab(tester, 'Menu');
    await tester.tap(find.byKey(const ValueKey('menu-logout')));
    await tester.pumpAndSettle();
    expect(login, findsOneWidget);
    expect(await saved(), isNull);
    await reopen(tester);
    expect(login, findsOneWidget);
  });

  testWidgets('401 em qualquer chamada apaga o login e volta pra tela de '
      'entrar', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    // Token revogado no servidor (ex.: sessão encerrada em outro aparelho).
    final casa = await repo.casaState;
    final token = casa.tokens.keys.single;
    await repo.logout(token);
    await openTab(tester, 'Menu');
    await tester.tap(find.text('Equipe'));
    await tester.pumpAndSettle();
    expect(login, findsOneWidget);
    expect(await saved(), isNull);
  });

  testWidgets('token guardado inválido: limpa e mostra o login', (
    tester,
  ) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    final casa = await repo.casaState;
    casa.tokens.clear();
    await reopen(tester);
    expect(login, findsOneWidget);
    expect(await saved(), isNull);
  });
}
