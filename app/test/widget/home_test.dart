import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  testWidgets('CT-15-03 sem código: estado vazio com chamada para agendar', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(tester, repo: seededRepo(clock), clock: clock);
    expect(find.byKey(const ValueKey('home-empty-next')), findsOneWidget);
    expect(find.text('Você ainda não tem horários'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Agendar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Agendar'));
    await tester.pumpAndSettle();
    expect(find.text('Serviço'.toUpperCase()), findsOneWidget);
  });

  testWidgets('CT-15-01 mostra o próximo horário com serviço, profissional e '
      'barbearia', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      clientCode: joaoCode,
    );
    final card = find.byKey(const ValueKey('home-next-booking'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Amanhã, 10:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Corte com Caio')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Barbearia Navalha'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('CT-15-02 pula o cancelado e mostra o seguinte ativo', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    final state = seededState();
    final i = state.bookings.indexWhere(
      (b) =>
          b.client.id == MockSeed.joaoId && b.status == BookingStatus.scheduled,
    );
    final old = state.bookings[i];
    state.bookings[i] = old.copyWith(
      status: BookingStatus.canceled,
      canceledBy: CanceledBy.staff,
    );
    final later = sp('2026-10-09T15:00:00');
    state.bookings.add(
      Booking(
        id: 'later',
        barbershopId: old.barbershopId,
        barbershopName: old.barbershopName,
        status: BookingStatus.scheduled,
        source: BookingSource.clientApp,
        startAt: later,
        endAt: later.add(const Duration(minutes: 30)),
        service: const BookingServiceRef(id: MockSeed.barbaId, name: 'Barba'),
        professional: MockSeed.helena,
        client: old.client,
        priceCents: 3000,
        createdAt: kNow,
      ),
    );
    await pumpCliente(
      tester,
      repo: MockClienteRepository(clock: clock, initialState: state),
      clock: clock,
      clientCode: joaoCode,
    );
    expect(find.text('Barba com Helena'), findsOneWidget);
    expect(find.text('Corte com Caio'), findsNothing);
  });

  testWidgets('CT-15-04 lista a Barbearia Navalha e abre a página dela', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(tester, repo: seededRepo(clock), clock: clock);
    expect(find.text('Barbearia Navalha'), findsOneWidget);
    expect(find.text('Pinheiros · São Paulo'), findsOneWidget);
    expect(find.text('A partir de R\$ 30,00'), findsOneWidget);

    await tester.tap(find.text('Barbearia Navalha'));
    await tester.pumpAndSettle();
    expect(find.text('SERVIÇOS'), findsOneWidget);
    expect(find.text('PROFISSIONAIS'), findsOneWidget);
  });

  testWidgets('CT-09-04 no Início o amarelo é só a aba ativa', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      clientCode: joaoCode,
    );
    expect(yellowTexts(tester), ['Início']);
    final horarios = tester.widget<Text>(find.text('Horários'));
    expect(horarios.style!.color, isNot(CortaTokens.dark.accent));
  });
}
