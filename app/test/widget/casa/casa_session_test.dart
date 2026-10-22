import 'dart:convert';

import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/presentation/casa/casa_app.dart';
import 'package:cortaaqui/presentation/casa/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'casa_harness.dart';

/// Decisão do PO: a Casa lembra o login (chave própria) até Sair ou 401.
/// O token fica no armazenamento seguro, nunca no SharedPreferences.
void main() {
  const key = SessionNotifier.kSession;
  final login = find.byKey(const ValueKey('login-submit'));
  late FixedClock clock;
  late MockCasaRepository repo;
  late Map<String, ApiProblem> faults;

  setUp(() {
    clock = FixedClock(kCasaNow);
    faults = {};
    repo = MockCasaRepository(
      clock: clock,
      initialState: MockSeed.build(sp('2026-10-07T09:00:00')),
      faultInjector: (op) => faults[op],
    );
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
          casaTokenStoreProvider.overrideWithValue(casaTokens),
        ],
        child: const CasaApp(config: casaConfig),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String?> saved() async =>
      (await SharedPreferences.getInstance()).getString(key);

  /// Nenhum valor do SharedPreferences contém o token.
  Future<void> expectTokenNotInPrefs(String token) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect('${prefs.get(k)}'.contains(token), isFalse, reason: k);
    }
  }

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
    expect(casaTokens.token, isNotNull);
    await reopen(tester);
    expect(login, findsNothing);
    expect(find.text('Agenda'), findsWidgets);
  });

  testWidgets('token vai pro armazenamento seguro, não pro SharedPreferences', (
    tester,
  ) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    final token = (await repo.casaState).tokens.keys.single;
    expect(casaTokens.token, token);
    await expectTokenNotInPrefs(token);
    expect(jsonDecode((await saved())!), isNot(contains('token')));
  });

  testWidgets('login antigo com token em texto puro migra na abertura', (
    tester,
  ) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    final token = casaTokens.token!;
    final prefs = await SharedPreferences.getInstance();
    final old = (jsonDecode((await saved())!) as Map)..['token'] = token;
    await prefs.setString(key, jsonEncode(old));
    casaTokens.token = null;
    await reopen(tester);
    expect(login, findsNothing);
    expect(casaTokens.token, token);
    await expectTokenNotInPrefs(token);
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
    expect(casaTokens.token, isNull);
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
    expect(casaTokens.token, isNull);
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
    expect(casaTokens.token, isNull);
  });

  for (final status in [403, 404]) {
    testWidgets('/auth/me com $status: avisa acesso desativado e volta pro '
        'login', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      faults['me'] = ApiProblem(
        status == 403 ? ErrorCode.forbidden : ErrorCode.notFound,
        status: status,
        title: 'x',
      );
      await reopen(tester);
      expect(find.text(kAccessRevokedMessage), findsOneWidget);
      expect(login, findsOneWidget);
      expect(casaTokens.token, isNull);
      expect(await saved(), isNull);
      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();
      expect(find.text(kAccessRevokedMessage), findsNothing);
      expect(login, findsOneWidget);
    });
  }

  testWidgets('403 em outra rota não sai do login', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.helenaEmail,
    );
    faults['getProfessionalCash'] = const ApiProblem(
      ErrorCode.forbidden,
      status: 403,
      title: 'Sem permissão',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CasaApp)),
    );
    final s = container.read(sessionProvider)!;
    await expectLater(
      container
          .read(casaApiProvider)
          .getProfessionalCash(
            s.token,
            barbershopId: s.shopId,
            professionalId: MockSeed.caioId,
            month: '2026-10',
          ),
      throwsA(isA<ApiProblem>()),
    );
    await tester.pumpAndSettle();
    expect(container.read(sessionProvider), isNotNull);
    expect(login, findsNothing);
    expect(casaTokens.token, s.token);
    expect(find.text(kAccessRevokedMessage), findsNothing);
  });
}
