import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/mock/mock_state.dart';
import 'package:cortaaqui/data/repositories/cliente_repository.dart';
import 'package:cortaaqui/presentation/cliente/cliente_app.dart';
import 'package:cortaaqui/presentation/cliente/providers.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const clienteConfig = AppConfig(
  flavor: Flavor.cliente,
  dataSource: DataSource.mock,
  apiBaseUrl: 'http://localhost',
);

/// Hora de Brasília -> instante.
DateTime sp(String local) => DateTime.parse('$local-03:00').toUtc();

/// "Hoje" dos testes: quarta, 07/10/2026 09:00 em Brasília.
final kNow = sp('2026-10-07T09:00:00');

/// Código do aparelho do João (cliente do seed), preso ao telefone dele. É o
/// aparelho que abre o APK mock. Nos testes que passam `clientCode: joaoCode`,
/// este aparelho é o do João.
const joaoCode = MockSeed.joaoDeviceCode;

/// Seed oficial montado em volta de [kNow]. João tem 1 futuro (amanhã 10:00
/// com o Caio), 1 concluído e 1 cancelado pela barbearia.
MockState seededState() => MockSeed.build(kNow);

Future<void> pumpCliente(
  WidgetTester tester, {
  required ClienteRepository repo,
  required Clock clock,
  bool introSeen = true,
  String? clientCode,
  String? location,
  AppConfig config = clienteConfig,
  bool deviceSeed = false,
  Map<String, Object> extraPrefs = const {},
}) async {
  // Aparelho preso: código e telefone salvos juntos. Hoje só o do João.
  // Por padrão o aparelho começa como o teste pede ([clientCode]); com
  // [deviceSeed] entra a sessão do seed do jeito que o APK sobe
  // (`deviceSeedOverrides`): João no modo mock, nada no modo api.
  SharedPreferences.setMockInitialValues({
    ...extraPrefs,
    if (introSeen) DeviceStore.kIntroSeen: true,
    if (clientCode != null) ...{
      DeviceStore.kClientCode: clientCode,
      DeviceStore.kBoundPhone: MockSeed.joaoPhone,
      DeviceStore.kClientName: 'João Almeida',
    },
  });
  tester.view.physicalSize = const Size(2400, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        clockProvider.overrideWithValue(clock),
        clienteRepositoryProvider.overrideWithValue(repo),
        if (deviceSeed) ...deviceSeedOverrides(config),
      ],
      child: ClienteApp(config: config, initialLocation: location),
    ),
  );
  await tester.pumpAndSettle();
}

const kDisconnectedText = 'Este aparelho foi desconectado pela barbearia.';

/// Fecha o aviso de aparelho desconectado (diálogo do `ClienteApp`).
Future<void> ackDisconnected(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('disconnected-ok')));
  await tester.pumpAndSettle();
}

/// Passa a introdução pelo "Pular".
Future<void> skipIntro(WidgetTester tester) async {
  await tester.tap(find.text('Pular'));
  await tester.pumpAndSettle();
}

MockClienteRepository seededRepo(Clock clock) =>
    MockClienteRepository(clock: clock, initialState: seededState());

/// Textos pintados de amarelo na tela (CT-09-04).
List<String> yellowTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((t) => t.style?.color == CortaTokens.dark.accent)
    .map((t) => t.data ?? '')
    .toList();
