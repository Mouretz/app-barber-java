import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/core/time/sao_paulo.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/availability.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

const agendar = '/agendar/${MockSeed.shopId}';

/// Código do aparelho de outra pessoa (UUID, como no contrato).
const kOutraPessoa = '00000000-0000-4000-8000-00000000beef';

/// Repositório que devolve uma lista fixa de livres (CT-01-17 e CT-01-25).
class FixedSlotsRepo extends MockClienteRepository {
  FixedSlotsRepo(Clock clock)
    : super(clock: clock, initialState: seededState());

  int availabilityCalls = 0;

  @override
  Future<Availability> getAvailability({
    required String barbershopId,
    required String serviceId,
    required String professionalId,
    required SpDate date,
  }) async {
    availabilityCalls++;
    // 08:00 a 20:30, de 30 em 30, sem 09:30 (para provar que a tela não
    // inventa horário).
    final slots = <AvailabilitySlot>[
      for (var m = 8 * 60; m <= 20 * 60 + 30; m += 30)
        if (m != 9 * 60 + 30)
          AvailabilitySlot(startAt: date.at(m), period: Period.ofMinute(m)),
    ];
    return Availability(
      date: date,
      professionalId: professionalId,
      serviceId: serviceId,
      slots: slots,
    );
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> choose(
  WidgetTester tester, {
  String service = MockSeed.corteId,
  String pro = MockSeed.caioId,
  String day = '2026-10-08',
}) async {
  await tapKey(tester, 'service-$service');
  await tapKey(tester, 'pro-$pro');
  await tapKey(tester, 'day-$day');
}

/// Horários na tela, na ordem (chave `slot-HH:mm`).
List<String> visibleSlots(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('slot-'),
      ),
    )
    .map((w) => (w.key! as ValueKey<String>).value.substring(5))
    .toList();

FilledButton continueButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('booking-continue')));

void main() {
  testWidgets('CT-01-16 o seletor mostra 14 dias, de 07/10 a 20/10', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: agendar,
    );
    final days = tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('day-'),
          ),
        )
        .map((w) => (w.key! as ValueKey<String>).value)
        .toList();
    expect(days, hasLength(14));
    expect(days.first, 'day-2026-10-07');
    expect(days.last, 'day-2026-10-20');
  });

  testWidgets('CT-01-24 Continuar só habilita com tudo escolhido; o '
      'profissional escolhido fica amarelo', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: agendar,
    );
    expect(continueButton(tester).onPressed, isNull);
    await tapKey(tester, 'service-${MockSeed.corteId}');
    expect(continueButton(tester).onPressed, isNull);
    await tapKey(tester, 'pro-${MockSeed.caioId}');
    expect(continueButton(tester).onPressed, isNull);

    final caio = tester.widget<Text>(
      find.byKey(const ValueKey('pro-name-${MockSeed.caioId}')),
    );
    final helena = tester.widget<Text>(
      find.byKey(const ValueKey('pro-name-${MockSeed.helenaId}')),
    );
    expect(caio.style!.color, CortaTokens.dark.accent);
    expect(helena.style!.color, CortaTokens.dark.text);
    expect(yellowTexts(tester), ['Caio']);

    await tapKey(tester, 'day-2026-10-08');
    await tapKey(tester, 'slot-09:00');
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('mostra só os livres do repositório: ocupado, bloqueio e combo', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: agendar,
    );
    // Quinta 08/10, Caio: João 10:00, Rafael 11:00–12:00 e bloqueio 14:00–15:00.
    await choose(tester);
    expect(visibleSlots(tester), ['08:00', '08:30', '09:00', '09:30', '10:30']);
    await tapKey(tester, 'period-AFTERNOON');
    expect(visibleSlots(tester), isNot(contains('14:00')));
    expect(visibleSlots(tester), isNot(contains('14:30')));
    expect(visibleSlots(tester), contains('15:00'));

    // Combo: 09:30 não cabe (10:00 ocupado) e 10:30 também não (11:00 ocupado).
    await tapKey(tester, 'service-${MockSeed.comboId}');
    expect(visibleSlots(tester), ['08:00', '08:30', '09:00']);
  });

  testWidgets('CT-01-17 / CT-01-25 turno só filtra a lista do repositório', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    final repo = FixedSlotsRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
    await choose(tester);
    final calls = repo.availabilityCalls;

    expect(visibleSlots(tester), [
      '08:00',
      '08:30',
      '09:00',
      '10:00',
      '10:30',
      '11:00',
      '11:30',
    ]);
    await tapKey(tester, 'period-AFTERNOON');
    expect(visibleSlots(tester), [
      '12:00',
      '12:30',
      '13:00',
      '13:30',
      '14:00',
      '14:30',
      '15:00',
      '15:30',
      '16:00',
      '16:30',
      '17:00',
      '17:30',
    ]);
    await tapKey(tester, 'period-EVENING');
    expect(visibleSlots(tester), [
      '18:00',
      '18:30',
      '19:00',
      '19:30',
      '20:00',
      '20:30',
    ]);
    expect(repo.availabilityCalls, calls, reason: 'trocar turno não recarrega');
  });

  testWidgets('CT-01-18 / CT-01-24 agenda o horário tocado, mostra sucesso e '
      'aparece em Meus horários', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
    await choose(tester);
    await tapKey(tester, 'slot-09:00');
    await tapKey(tester, 'booking-continue');

    expect(find.text('Confirmar horário'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('confirm-name')),
      'Ana Lima',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-phone')),
      '(31) 99876-5432',
    );
    await tapKey(tester, 'confirm-submit');

    expect(find.byKey(const ValueKey('booking-success')), findsOneWidget);
    expect(find.text('Horário marcado'), findsOneWidget);
    expect(find.text('Amanhã, 09:00'), findsOneWidget);

    final s = await repo.state;
    final created = s.bookings.where((b) => b.client.name == 'Ana Lima');
    expect(created, hasLength(1));
    expect(created.single.startAt, sp('2026-10-08T09:00:00'));
    expect(created.single.source, BookingSource.clientApp);
    expect(s.clients.any((c) => c.phone == '+5531998765432'), isTrue);

    // Aceito: só agora o aparelho guarda o código, preso a este telefone.
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(DeviceStore.kClientCode);
    expect(code, isNotNull);
    expect(prefs.getString(DeviceStore.kBoundPhone), '+5531998765432');
    expect(s.codes[code], created.single.client.id);
    expect(
      find.text('Dá para cancelar até 2 horas antes, em Horários.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ver meus horários'));
    await tester.pumpAndSettle();
    expect(find.text('Meus horários'), findsOneWidget);
    expect(find.text('Amanhã, 09:00'), findsOneWidget);
    expect(find.text('Corte com Caio'), findsOneWidget);
  });

  /// Abre a folha de confirmação para amanhã 09:00 com o Caio.
  Future<void> openConfirm(WidgetTester tester) async {
    await choose(tester);
    await tapKey(tester, 'slot-09:00');
    await tapKey(tester, 'booking-continue');
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String name,
    required String phone,
  }) async {
    await tester.enterText(find.byKey(const ValueKey('confirm-name')), name);
    await tester.enterText(find.byKey(const ValueKey('confirm-phone')), phone);
    await tapKey(tester, 'confirm-submit');
  }

  TextField phoneField(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const ValueKey('confirm-phone')));

  testWidgets(
    'CT-04-15 telefone do seed (preso a outro aparelho): texto exato, '
    'nada salvo e o campo continua livre',
    (tester) async {
      final clock = FixedClock(kNow);
      final repo = seededRepo(clock);
      await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
      final before = (await repo.state).bookings.length;
      await openConfirm(tester);
      await fillAndSubmit(tester, name: 'João', phone: '(11) 98765-4321');

      expect(
        find.text(
          'Esse telefone já está em outro aparelho. Fale com a barbearia.',
        ),
        findsOneWidget,
      );
      expect(find.text('Horário marcado'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DeviceStore.kClientCode), isNull);
      expect(prefs.getString(DeviceStore.kBoundPhone), isNull);
      expect(phoneField(tester).readOnly, isFalse);
      final s = await repo.state;
      expect(s.bookings, hasLength(before));
      expect(s.codes.keys, [MockSeed.joaoDeviceCode]);

      // Com outro número, o mesmo aparelho agenda e aí fica preso.
      await fillAndSubmit(tester, name: 'Ana', phone: '(31) 99876-5432');
      expect(find.text('Horário marcado'), findsOneWidget);
      expect(prefs.getString(DeviceStore.kBoundPhone), '+5531998765432');
    },
  );

  testWidgets(
    '1º agendamento recusado por limite: não salva o código nem trava '
    'o campo (regra do PO)',
    (tester) async {
      final clock = FixedClock(kNow);
      final repo = seededRepo(clock);
      // João com 2 futuros pelo app e o aparelho dele liberado pelo gerente.
      await repo.createClientBooking(
        barbershopId: MockSeed.shopId,
        idempotencyKey: 'joao-2',
        clientCode: joaoCode,
        request: ClientBookingRequest(
          serviceId: MockSeed.corteId,
          professionalId: MockSeed.helenaId,
          startAt: sp('2026-10-09T16:00:00'),
          client: const ClientInfo(
            name: 'João Almeida',
            phone: MockSeed.joaoPhone,
          ),
        ),
      );
      await repo.releaseClientDevice(
        barbershopId: MockSeed.shopId,
        clientId: MockSeed.joaoId,
      );
      await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
      await openConfirm(tester);
      await fillAndSubmit(tester, name: 'João', phone: '+55 11 98765-4321');

      expect(
        find.text(
          clientMessageFor(
            const ApiProblem(ErrorCode.bookingLimitReached, status: 422),
          ),
        ),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DeviceStore.kClientCode), isNull);
      expect(phoneField(tester).readOnly, isFalse);
      expect(
        (await repo.state).codes,
        isEmpty,
        reason: 'nenhum aparelho preso',
      );
    },
  );

  testWidgets('1º agendamento com horário ocupado: volta para escolher, sem '
      'salvar o código', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
    await openConfirm(tester);
    await repo.createClientBooking(
      barbershopId: MockSeed.shopId,
      idempotencyKey: 'outra-pessoa',
      clientCode: kOutraPessoa,
      request: ClientBookingRequest(
        serviceId: MockSeed.corteId,
        professionalId: MockSeed.caioId,
        startAt: sp('2026-10-08T09:00:00'),
        client: const ClientInfo(name: 'Outro', phone: '41999998888'),
      ),
    );
    await fillAndSubmit(tester, name: 'Ana', phone: '31998765432');
    expect(
      find.text('Esse horário acabou de ficar indisponível'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), isNull);
    expect(
      (await repo.state).codes.keys,
      unorderedEquals([MockSeed.joaoDeviceCode, kOutraPessoa]),
    );
  });

  testWidgets('aparelho preso: telefone travado com o número salvo e nome '
      'preenchido', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      location: agendar,
      clientCode: joaoCode,
    );
    await openConfirm(tester);
    expect(phoneField(tester).readOnly, isTrue);
    expect(phoneField(tester).controller!.text, '(11) 98765-4321');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('confirm-name')))
          .controller!
          .text,
      'João Almeida',
    );
    expect(
      find.text('Este aparelho está ligado a este telefone.'),
      findsOneWidget,
    );
    await tapKey(tester, 'confirm-submit');
    expect(find.text('Horário marcado'), findsOneWidget);
    final s = await repo.state;
    expect(
      s.bookings
          .where((b) => b.startAt == sp('2026-10-08T09:00:00'))
          .single
          .client
          .id,
      MockSeed.joaoId,
    );
  });

  testWidgets('código revogado (troca de celular) ao agendar: o aparelho volta '
      'ao estado sem código e o telefone destrava', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      location: agendar,
      clientCode: joaoCode,
    );
    await openConfirm(tester);
    await repo.releaseClientDevice(
      barbershopId: MockSeed.shopId,
      clientId: MockSeed.joaoId,
    );
    await tapKey(tester, 'confirm-submit');

    expect(find.text('Horário marcado'), findsNothing);
    // O aviso sai uma vez, na própria folha, e não por baixo dela.
    expect(
      find.text('Este aparelho foi desconectado pela barbearia.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('disconnected-notice')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), isNull);
    expect(prefs.getString(DeviceStore.kBoundPhone), isNull);
    expect(phoneField(tester).readOnly, isFalse);
    expect(phoneField(tester).controller!.text, isEmpty);

    // Agendando de novo neste aparelho com o telefone do João, ele fica preso
    // ao João outra vez, com um código novo.
    await fillAndSubmit(tester, name: 'João', phone: '(11) 98765-4321');
    expect(find.text('Horário marcado'), findsOneWidget);
    final code = prefs.getString(DeviceStore.kClientCode);
    expect(code, isNot(joaoCode));
    expect((await repo.state).codes[code], MockSeed.joaoId);
  });

  testWidgets('toque duplo no Confirmar cria um agendamento só', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      location: agendar,
      clientCode: joaoCode,
    );
    final before = (await repo.state).bookings.length;
    await openConfirm(tester);

    final submit = find.byKey(const ValueKey('confirm-submit'));
    await tester.tap(submit);
    await tester.tap(submit, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Horário marcado'), findsOneWidget);
    expect((await repo.state).bookings.length, before + 1);
  });

  testWidgets('CT-01-26 conflito na confirmação: avisa, recarrega e volta '
      'para escolher', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
    await choose(tester);
    await tapKey(tester, 'slot-09:00');
    await tapKey(tester, 'booking-continue');
    await tester.enterText(find.byKey(const ValueKey('confirm-name')), 'Ana');
    await tester.enterText(
      find.byKey(const ValueKey('confirm-phone')),
      '31998765432',
    );

    // Outra pessoa pega o horário enquanto a folha está aberta.
    await repo.createClientBooking(
      barbershopId: MockSeed.shopId,
      idempotencyKey: 'outra-pessoa',
      clientCode: kOutraPessoa,
      request: ClientBookingRequest(
        serviceId: MockSeed.corteId,
        professionalId: MockSeed.caioId,
        startAt: sp('2026-10-08T09:00:00'),
        client: const ClientInfo(name: 'Outro', phone: '41999998888'),
      ),
    );

    await tapKey(tester, 'confirm-submit');

    expect(find.text('Confirmar horário'), findsNothing);
    expect(
      find.text('Esse horário acabou de ficar indisponível'),
      findsOneWidget,
    );
    expect(visibleSlots(tester), isNot(contains('09:00')));
    expect(continueButton(tester).onPressed, isNull);
    expect(
      (await repo.state).bookings.where((b) => b.client.name == 'Ana'),
      isEmpty,
    );
  });

  testWidgets('telefone inválido: mensagem clara e nada gravado', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock, location: agendar);
    final before = (await repo.state).bookings.length;
    await choose(tester);
    await tapKey(tester, 'slot-09:00');
    await tapKey(tester, 'booking-continue');
    await tester.enterText(find.byKey(const ValueKey('confirm-name')), 'Ana');
    await tester.enterText(
      find.byKey(const ValueKey('confirm-phone')),
      '987654321',
    );
    await tapKey(tester, 'confirm-submit');

    expect(find.textContaining('Telefone inválido'), findsOneWidget);
    expect(find.text('Confirmar horário'), findsOneWidget);
    expect((await repo.state).bookings.length, before);
  });

  testWidgets('limite de 2: o 3º no aparelho do João é recusado com mensagem', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    // João já tem 1 futuro no seed; marca mais 1 pelo app.
    await repo.createClientBooking(
      barbershopId: MockSeed.shopId,
      idempotencyKey: 'joao-2',
      clientCode: joaoCode,
      request: ClientBookingRequest(
        serviceId: MockSeed.corteId,
        professionalId: MockSeed.helenaId,
        startAt: sp('2026-10-09T16:00:00'),
        client: const ClientInfo(
          name: 'João Almeida',
          phone: MockSeed.joaoPhone,
        ),
      ),
    );
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      location: agendar,
      clientCode: joaoCode,
    );
    await openConfirm(tester);
    await tapKey(tester, 'confirm-submit');

    expect(
      find.text(
        clientMessageFor(
          const ApiProblem(ErrorCode.bookingLimitReached, status: 422),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Horário marcado'), findsNothing);
    // Recusa num aparelho já preso não solta o aparelho.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), joaoCode);
  });

  testWidgets('dia sem expediente mostra estado vazio', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: agendar,
    );
    // Domingo 11/10: Caio não atende.
    await choose(tester, day: '2026-10-11');
    expect(find.byKey(const ValueKey('slots-empty-day')), findsOneWidget);
  });
}
