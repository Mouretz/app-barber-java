import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

const apiConfig = AppConfig(
  flavor: Flavor.cliente,
  dataSource: DataSource.api,
  apiBaseUrl: 'http://localhost',
);

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('modo API: o botão "Entrar como cliente novo" não aparece', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      clientCode: joaoCode,
      location: '/menu',
      config: apiConfig,
    );
    expect(find.text('Menu'), findsWidgets); // título e aba
    expect(find.byKey(const ValueKey('menu-new-client')), findsNothing);
    expect(find.text('Entrar como cliente novo'), findsNothing);
  });

  testWidgets(
    'CT-00-46 modo mock: "Entrar como cliente novo" apaga o aparelho do João, '
    'volta ao Início, e os telefones do Rafael e do João dão '
    'PHONE_ON_OTHER_DEVICE',
    (tester) async {
      final clock = FixedClock(kNow);
      final repo = seededRepo(clock);
      // Como o APK mock sobe: o aparelho já vem preso ao João.
      await pumpCliente(
        tester,
        repo: repo,
        clock: clock,
        deviceSeed: true,
        location: '/menu',
      );
      expect(
        find.text('Este aparelho está ligado ao telefone (11) 98765-4321.'),
        findsOneWidget,
      );

      await tapKey(tester, 'menu-new-client');
      expect(find.text('Entrar como cliente novo?'), findsOneWidget);
      await tapKey(tester, 'new-client-confirm');

      // Volta ao Início (a introdução é da instalação e já foi vista), sem o
      // João nem o horário dele.
      expect(find.byKey(const ValueKey('home-empty-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-next-booking')), findsNothing);
      expect(find.text('Você ainda não tem horários'), findsOneWidget);
      expect(find.text('Pular'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DeviceStore.kClientCode), isNull);
      expect(prefs.getString(DeviceStore.kBoundPhone), isNull);
      expect(prefs.getString(DeviceStore.kClientName), isNull);
      expect(prefs.getBool(DeviceStore.kIntroSeen), isTrue);
      // O "servidor" do mock não mudou: o João continua preso ao código dele.
      expect((await repo.state).codes[joaoCode], MockSeed.joaoId);

      // Agendar: telefone livre e vazio; o do Rafael (aparelho fictício do
      // seed) e o do João (código apagado, mas ainda preso no "servidor") são
      // recusados.
      await tester.tap(find.widgetWithText(FilledButton, 'Agendar'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'service-${MockSeed.corteId}');
      await tapKey(tester, 'pro-${MockSeed.caioId}');
      await tapKey(tester, 'day-2026-10-08');
      await tapKey(tester, 'slot-09:00');
      await tapKey(tester, 'booking-continue');
      final phone = tester.widget<TextField>(
        find.byKey(const ValueKey('confirm-phone')),
      );
      expect(phone.readOnly, isFalse);
      expect(phone.controller!.text, isEmpty);
      final before = (await repo.state).bookings.length;
      for (final number in ['(21) 91234-5678', '(11) 98765-4321']) {
        await tester.enterText(
          find.byKey(const ValueKey('confirm-name')),
          'Teste',
        );
        await tester.enterText(
          find.byKey(const ValueKey('confirm-phone')),
          number,
        );
        await tapKey(tester, 'confirm-submit');
        expect(
          find.text(
            'Esse telefone já está em outro aparelho. Fale com a barbearia.',
          ),
          findsOneWidget,
          reason: number,
        );
        expect(prefs.getString(DeviceStore.kClientCode), isNull);
      }
      expect((await repo.state).bookings, hasLength(before));
    },
  );

  testWidgets('modo mock, aparelho limpo: o menu diz que o 1º agendamento liga '
      'o aparelho', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: '/menu',
    );
    expect(
      find.text('Seu primeiro agendamento liga este aparelho ao seu telefone.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('menu-new-client')), findsOneWidget);
  });
}
