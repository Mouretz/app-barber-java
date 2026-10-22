import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/storage/casa_token_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/core/time/sao_paulo.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/repositories/casa_repository.dart';
import 'package:cortaaqui/presentation/casa/casa_app.dart';
import 'package:cortaaqui/presentation/casa/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const casaConfig = AppConfig(
  flavor: Flavor.casa,
  dataSource: DataSource.mock,
  apiBaseUrl: 'http://localhost',
);

/// Token da Casa nos testes (no aparelho é o armazenamento seguro).
final casaTokens = MemoryCasaTokenStore();

DateTime sp(String local) => DateTime.parse('$local-03:00').toUtc();

/// "Hoje" dos testes da Casa: quinta 08/10/2026 09:00 (dia do seed com João
/// 10:00 e Rafael 11:00 com o Caio, e bloqueio do Caio 14:00–15:00).
final kCasaNow = sp('2026-10-08T09:00:00');

/// Seed montado na véspera (o seed põe os horários no dia seguinte a "agora").
MockCasaRepository casaRepo(Clock clock, {MockCasaState? casa}) =>
    MockCasaRepository(
      clock: clock,
      initialState: MockSeed.build(sp('2026-10-07T09:00:00')),
      initialCasa: casa,
    );

Future<void> pumpCasa(
  WidgetTester tester, {
  required CasaRepository repo,
  required Clock clock,
  String? email,
}) async {
  SharedPreferences.setMockInitialValues({});
  casaTokens.token = null;
  tester.view.physicalSize = const Size(1600, 6000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
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
  if (email != null) await loginAs(tester, email);
}

Future<void> loginAs(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const ValueKey('login-email')), email);
  await tester.enterText(
    find.byKey(const ValueKey('login-password')),
    MockCasaSeed.mockPassword,
  );
  await tester.tap(find.byKey(const ValueKey('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

abstract final class SpDateX {
  static const thu = SpDate(2026, 10, 8);
}
