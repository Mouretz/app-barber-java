import 'package:cortaaqui/app.dart';
import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/presentation/casa/providers.dart'
    show casaRepositoryProvider;
import 'package:cortaaqui/presentation/cliente/providers.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

      if (flavor == Flavor.casa) {
        // Casa: login do gerente do seed e a Agenda.
        SharedPreferences.setMockInitialValues({});
        final clock = FixedClock(DateTime.utc(2026, 10, 7, 12));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appConfigProvider.overrideWithValue(config),
              clockProvider.overrideWithValue(clock),
              casaRepositoryProvider.overrideWithValue(
                MockCasaRepository(clock: clock),
              ),
            ],
            child: CortaAquiApp(config: config),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('login-email')),
          MockCasaSeed.marinaEmail,
        );
        await tester.enterText(
          find.byKey(const ValueKey('login-password')),
          MockCasaSeed.mockPassword,
        );
        await tester.tap(find.byKey(const ValueKey('login-submit')));
        await tester.pumpAndSettle();
        expect(find.text('Agenda da casa'), findsOneWidget);
      } else {
        // Cliente: telas de verdade, com o repositório mock e a intro já vista.
        SharedPreferences.setMockInitialValues({DeviceStore.kIntroSeen: true});
        final clock = FixedClock(DateTime.utc(2026, 10, 7, 12));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appConfigProvider.overrideWithValue(config),
              clockProvider.overrideWithValue(clock),
              clienteRepositoryProvider.overrideWithValue(
                MockClienteRepository(clock: clock),
              ),
            ],
            child: CortaAquiApp(config: config),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Barbearia Navalha'), findsOneWidget);
      }

      final firstLabel = flavor == Flavor.cliente ? 'Início' : 'Agenda';
      final label = tester.widget<Text>(find.text(firstLabel).last);
      expect(label.style!.color, CortaTokens.dark.accent);
    });
  }
}
