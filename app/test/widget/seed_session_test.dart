import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/booking.dart';
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

/// Todas as chaves salvas no aparelho (para "fechar e abrir" o app).
Future<Map<String, Object>> savedPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final k in prefs.getKeys()) k: prefs.get(k)!};
}

void main() {
  testWidgets('APK mock, 1ª abertura: a intro aparece e depois o Início mostra '
      'o próximo horário do João, com o aparelho já preso a ele', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      introSeen: false,
      deviceSeed: true,
    );

    // A intro de primeira abertura continua.
    expect(find.text('Pular'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), MockSeed.joaoDeviceCode);
    expect(prefs.getString(DeviceStore.kBoundPhone), MockSeed.joaoPhone);
    expect(prefs.getString(DeviceStore.kClientName), 'João Almeida');
    expect(prefs.getBool(DeviceStore.kSeedSessionApplied), isTrue);

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('home-next-booking'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Amanhã, 10:00')),
      findsOneWidget,
    );

    // Horários: 1 futuro e 2 no histórico, sem aviso de desconexão.
    await tester.tap(find.text('Horários'));
    await tester.pumpAndSettle();
    expect(find.text('Corte com Caio'), findsOneWidget);
    await tapKey(tester, 'scope-past');
    expect(find.text('Corte + Barba com Helena'), findsOneWidget);
    expect(find.text('Barba com Caio'), findsOneWidget);
    expect(
      find.text('Este aparelho foi desconectado pela barbearia.'),
      findsNothing,
    );

    // Agendar pela página da barbearia: telefone do João travado.
    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    final shop = find.text('Barbearia Navalha').last;
    await tester.ensureVisible(shop);
    await tester.tap(shop);
    await tester.pumpAndSettle();
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
    expect(phone.readOnly, isTrue);
    expect(phone.controller!.text, '(11) 98765-4321');
  });

  testWidgets(
    'modo api: nenhuma sessão do seed, o aparelho começa sem código',
    (tester) async {
      final clock = FixedClock(kNow);
      await pumpCliente(
        tester,
        repo: seededRepo(clock),
        clock: clock,
        config: apiConfig,
        deviceSeed: true,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DeviceStore.kClientCode), isNull);
      expect(prefs.getString(DeviceStore.kBoundPhone), isNull);
      expect(prefs.getBool(DeviceStore.kSeedSessionApplied), isNull);
      expect(find.byKey(const ValueKey('home-empty-next')), findsOneWidget);
      expect(find.text('Você ainda não tem horários'), findsOneWidget);
    },
  );

  testWidgets('APK mock: depois de "Entrar como cliente novo", fechar e abrir '
      'não traz o João de volta', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      deviceSeed: true,
      location: '/menu',
    );
    await tapKey(tester, 'menu-new-client');
    await tapKey(tester, 'new-client-confirm');
    expect(find.byKey(const ValueKey('home-empty-next')), findsOneWidget);

    // Fecha e abre com o que ficou salvo no aparelho.
    final saved = await savedPrefs();
    expect(saved.containsKey(DeviceStore.kClientCode), isFalse);
    await tester.pumpWidget(const SizedBox());
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      deviceSeed: true,
      extraPrefs: saved,
    );
    expect(find.byKey(const ValueKey('home-empty-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-next-booking')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), isNull);
    // O "servidor" do mock continua com o João preso ao código antigo.
    expect((await repo.state).codes[MockSeed.joaoDeviceCode], MockSeed.joaoId);
  });

  testWidgets('APK mock: aparelho que já tem o próprio código não é trocado '
      'pelo do João', (tester) async {
    const proprio = '00000000-0000-4000-8000-00000000abcd';
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    // A Ana já agendou neste aparelho (APK mock de antes da sessão do seed).
    await repo.createClientBooking(
      barbershopId: MockSeed.shopId,
      idempotencyKey: 'ana',
      clientCode: proprio,
      request: ClientBookingRequest(
        serviceId: MockSeed.corteId,
        professionalId: MockSeed.helenaId,
        startAt: sp('2026-10-09T16:00:00'),
        client: const ClientInfo(name: 'Ana', phone: '(31) 99876-5432'),
      ),
    );
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      deviceSeed: true,
      extraPrefs: {
        DeviceStore.kClientCode: proprio,
        DeviceStore.kBoundPhone: '+5531998765432',
        DeviceStore.kClientName: 'Ana',
      },
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), proprio);
    expect(prefs.getString(DeviceStore.kBoundPhone), '+5531998765432');
    expect(prefs.getBool(DeviceStore.kSeedSessionApplied), isTrue);
    expect(find.byKey(const ValueKey('home-next-booking')), findsOneWidget);
  });
}
