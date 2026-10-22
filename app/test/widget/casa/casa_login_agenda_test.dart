import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/data/models/barbershop.dart';
import 'package:cortaaqui/data/models/staff.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'casa_harness.dart';

const joaoBooking = '6f1c2a10-0000-4000-8000-0000000000d1';
const rafaelBooking = '6f1c2a10-0000-4000-8000-0000000000d4';

void main() {
  late FixedClock clock;
  late MockCasaRepository repo;

  setUp(() {
    clock = FixedClock(kCasaNow);
    repo = casaRepo(clock);
  });

  testWidgets('login errado mostra a mesma mensagem e não entra', (
    tester,
  ) async {
    await pumpCasa(tester, repo: repo, clock: clock);
    await tester.enterText(
      find.byKey(const ValueKey('login-email')),
      MockCasaSeed.marinaEmail,
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'senha-errada',
    );
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    expect(find.text('Agenda da casa'), findsNothing);
  });

  testWidgets('CT-02-01 gerente sem agenda própria: "Agenda da casa", '
      'seletor só com ativos e troca de profissional', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.marinaEmail,
    );
    expect(find.text('Agenda da casa'), findsOneWidget);
    expect(find.text('Minha agenda'), findsNothing);
    expect(
      find.byKey(const ValueKey('pro-${MockSeed.caioId}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pro-${MockSeed.helenaId}')),
      findsOneWidget,
    );
    // Caio primeiro: João às 10:00.
    expect(find.byKey(const ValueKey('booking-$joaoBooking')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pro-${MockSeed.helenaId}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('booking-$joaoBooking')), findsNothing);
    // Helena começa 10:00: 08:00 fica cinza, sem ação (CT-02-03).
    expect(find.text('Fora do expediente'), findsWidgets);
  });

  testWidgets('seletor da agenda não mostra profissional desativado', (
    tester,
  ) async {
    final g = (await repo.login(
      email: MockCasaSeed.marinaEmail,
      password: MockCasaSeed.mockPassword,
    )).accessToken;
    await repo.updateProfessional(
      g,
      barbershopId: MockSeed.shopId,
      professionalId: MockSeed.helenaId,
      active: false,
    );
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.marinaEmail,
    );
    expect(
      find.byKey(const ValueKey('pro-${MockSeed.helenaId}')),
      findsNothing,
    );
  });

  testWidgets('CT-02-02 profissional: "Minha agenda", sem seletor', (
    tester,
  ) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    expect(find.text('Minha agenda'), findsOneWidget);
    expect(find.byKey(const ValueKey('pro-${MockSeed.caioId}')), findsNothing);
    expect(find.byKey(const ValueKey('booking-$joaoBooking')), findsOneWidget);
  });

  testWidgets('CT-02-24 destaca só a marcação com overlapsBlock', (
    tester,
  ) async {
    final t = (await repo.login(
      email: MockCasaSeed.caioEmail,
      password: MockCasaSeed.mockPassword,
    )).accessToken;
    final day = SpDateX.thu;
    await repo.createBlock(
      t,
      barbershopId: MockSeed.shopId,
      professionalId: MockSeed.caioId,
      startAt: day.at(9 * 60 + 30),
      endAt: day.at(10 * 60 + 30),
    );
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    expect(find.byKey(const ValueKey('overlap-$joaoBooking')), findsOneWidget);
    expect(find.byKey(const ValueKey('overlap-$rafaelBooking')), findsNothing);
  });

  testWidgets('CT-07-03 folga depois de marcado: marcação continua e fica '
      'destacada', (tester) async {
    final g = (await repo.login(
      email: MockCasaSeed.marinaEmail,
      password: MockCasaSeed.mockPassword,
    )).accessToken;
    await repo.createTimeOff(
      g,
      barbershopId: MockSeed.shopId,
      professionalId: MockSeed.caioId,
      startAt: SpDateX.thu.at(0),
      endAt: SpDateX.thu.addDays(1).at(0),
    );
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    expect(find.byKey(const ValueKey('outside-$joaoBooking')), findsOneWidget);
  });

  testWidgets('CT-02-05/06 livre abre Marcar e Bloquear; marcado abre '
      'Concluir, Falta e Cancelar', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await tester.tap(find.byKey(const ValueKey('slot-09:00')));
    await tester.pumpAndSettle();
    expect(find.text('Marcar'), findsOneWidget);
    expect(find.text('Bloquear'), findsOneWidget);
    Navigator.of(tester.element(find.text('Marcar'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('booking-$joaoBooking')));
    await tester.pumpAndSettle();
    expect(find.text('Concluir'), findsOneWidget);
    expect(find.text('Marcar falta'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('CT-06-07 balcão sem telefone entra na agenda com "Sem '
      'telefone"', (tester) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await tester.tap(find.byKey(const ValueKey('slot-09:00')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action-book')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('book-name')), 'Zeca');
    await tester.tap(find.byKey(const ValueKey('book-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Zeca'), findsOneWidget);
    expect(find.textContaining('Sem telefone'), findsOneWidget);
  });

  testWidgets('SLOT_TAKEN mostra "Horário ocupado" e fica na folha', (
    tester,
  ) async {
    final r = MockCasaRepository(
      clock: clock,
      initialState: MockSeed.build(sp('2026-10-07T09:00:00')),
      faultInjector: (op) => op == 'createStaffBooking'
          ? const ApiProblem(ErrorCode.slotTaken, status: 409)
          : null,
    );
    await pumpCasa(
      tester,
      repo: r,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await tester.tap(find.byKey(const ValueKey('slot-09:00')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action-book')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('book-name')), 'Zeca');
    await tester.tap(find.byKey(const ValueKey('book-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Horário ocupado'), findsOneWidget);
    expect(find.byKey(const ValueKey('book-submit')), findsOneWidget);
  });

  testWidgets('CONCURRENT_UPDATE: mensagem, fica na folha com as escolhas e '
      'tentar de novo usa a mesma chave', (tester) async {
    var fail = true;
    final keys = <String>[];
    final shared = MockSeed.build(sp('2026-10-07T09:00:00'));
    late MockCasaRepository r;
    r = MockCasaRepository(
      clock: clock,
      initialState: shared,
      faultInjector: (op) {
        if (op != 'createStaffBooking') return null;
        if (fail) {
          fail = false;
          return const ApiProblem(ErrorCode.concurrentUpdate, status: 409);
        }
        return null;
      },
    );
    final spy = _KeySpy(r, keys);
    await pumpCasa(
      tester,
      repo: spy,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await tester.tap(find.byKey(const ValueKey('slot-09:00')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('svc-${MockSeed.barbaId}')));
    await tester.enterText(find.byKey(const ValueKey('book-name')), 'Zeca');
    await tester.tap(find.byKey(const ValueKey('book-submit')));
    await tester.pumpAndSettle();
    expect(find.text(kConcurrentUpdateMessage), findsOneWidget);
    // Continua na folha, com nome e serviço escolhidos.
    expect(find.widgetWithText(TextField, 'Zeca'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('svc-${MockSeed.barbaId}')),
    );
    expect(chip.selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('book-submit')));
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(1));
    expect(find.text('Zeca'), findsOneWidget);
    expect(
      shared.bookings.where((b) => b.client.name == 'Zeca').single.service.id,
      MockSeed.barbaId,
    );
  });

  testWidgets('CONCURRENT_UPDATE ao concluir: fica na folha de ações', (
    tester,
  ) async {
    clock.set(sp('2026-10-08T10:10:00'));
    final r = MockCasaRepository(
      clock: clock,
      initialState: MockSeed.build(sp('2026-10-07T09:00:00')),
      faultInjector: (op) => op == 'changeBookingStatus'
          ? const ApiProblem(ErrorCode.concurrentUpdate, status: 409)
          : null,
    );
    await pumpCasa(
      tester,
      repo: r,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await tester.tap(find.byKey(const ValueKey('booking-$joaoBooking')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-COMPLETED')));
    await tester.pumpAndSettle();
    expect(find.text(kConcurrentUpdateMessage), findsOneWidget);
    expect(find.text('Concluir'), findsOneWidget);
  });

  testWidgets('CT-02-23/CT-00-45 STATUS_CHANGED: aviso, recarrega e tira as '
      'ações', (tester) async {
    clock.set(sp('2026-10-08T10:10:00'));
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.caioEmail,
    );
    await tester.tap(find.byKey(const ValueKey('booking-$joaoBooking')));
    await tester.pumpAndSettle();
    // O gerente conclui enquanto o Caio está com a folha aberta.
    final g = (await repo.login(
      email: MockCasaSeed.marinaEmail,
      password: MockCasaSeed.mockPassword,
    )).accessToken;
    await repo.changeBookingStatus(
      g,
      barbershopId: MockSeed.shopId,
      bookingId: joaoBooking,
      idempotencyKey: 'g-1',
      status: BookingStatus.completed,
    );
    await tester.tap(find.byKey(const ValueKey('status-NO_SHOW')));
    await tester.pumpAndSettle();
    expect(
      find.text('Esse horário já tinha mudado. A agenda foi atualizada.'),
      findsOneWidget,
    );
    expect(find.text('Concluído'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('booking-$joaoBooking')));
    await tester.pumpAndSettle();
    expect(find.text('Marcar falta'), findsNothing);
  });

  testWidgets('CT-09-04 amarelo só na aba ativa e no profissional escolhido', (
    tester,
  ) async {
    await pumpCasa(
      tester,
      repo: repo,
      clock: clock,
      email: MockCasaSeed.marinaEmail,
    );
    final yellowTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.color == CortaTokens.dark.accent)
        .map((t) => t.data)
        .toList();
    expect(yellowTexts, ['Agenda']);
    final rings = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.border is Border &&
              (d.border! as Border).top.color == CortaTokens.dark.accent;
        });
    expect(rings, hasLength(1));
  });
}

/// Repositório que anota a `Idempotency-Key` de cada marcação.
class _KeySpy extends MockCasaRepository {
  _KeySpy(this.inner, this.keys) : super(clock: inner.clock);

  final MockCasaRepository inner;
  final List<String> keys;

  @override
  Future<StaffSession> login({
    required String email,
    required String password,
  }) => inner.login(email: email, password: password);

  @override
  Future<Agenda> getAgenda(
    String token, {
    required String barbershopId,
    required date,
    String? professionalId,
  }) => inner.getAgenda(
    token,
    barbershopId: barbershopId,
    date: date,
    professionalId: professionalId,
  );

  @override
  Future<List<Service>> activeServices({required String barbershopId}) =>
      inner.activeServices(barbershopId: barbershopId);

  @override
  Future<Booking> createStaffBooking(
    String token, {
    required String barbershopId,
    required String idempotencyKey,
    required StaffBookingRequest request,
  }) {
    keys.add(idempotencyKey);
    return inner.createStaffBooking(
      token,
      barbershopId: barbershopId,
      idempotencyKey: idempotencyKey,
      request: request,
    );
  }
}
