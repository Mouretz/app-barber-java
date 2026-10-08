import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const joaoNext = '6f1c2a10-0000-4000-8000-0000000000d1'; // amanhã 10:00

void main() {
  testWidgets('CT-04-01 / CT-04-11 próximos e histórico, com "Cancelado pela '
      'barbearia"', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      clientCode: joaoCode,
      location: '/horarios',
    );
    expect(find.text('Meus horários'), findsOneWidget);
    expect(find.text('Amanhã, 10:00'), findsOneWidget);
    expect(find.text('Agendado'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-$joaoNext')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scope-past')));
    await tester.pumpAndSettle();
    expect(find.text('Concluído'), findsOneWidget);
    expect(find.text('Cancelado pela barbearia'), findsOneWidget);
    expect(find.textContaining('Cancelar horário'), findsNothing);
  });

  testWidgets('CT-04-12 / CT-04-05 cliente cancela: sai dos próximos e aparece '
      'como "Cancelado"', (tester) async {
    final clock = FixedClock(kNow);
    final repo = seededRepo(clock);
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      clientCode: joaoCode,
      location: '/horarios',
    );
    await tester.tap(find.byKey(const ValueKey('cancel-$joaoNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Horário cancelado.'), findsOneWidget);
    expect(find.text('Nenhum horário marcado'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scope-past')));
    await tester.pumpAndSettle();
    expect(find.text('Cancelado'), findsOneWidget);
    expect(find.text('Cancelado pela barbearia'), findsOneWidget); // o do seed

    final s = await repo.state;
    final b = s.bookings.firstWhere((x) => x.id == joaoNext);
    expect(b.status, BookingStatus.canceled);
    expect(b.canceledBy, CanceledBy.client);
  });

  testWidgets('CT-04-04 com 2h01 o botão aparece', (tester) async {
    final clock = FixedClock(sp('2026-10-08T07:59:00'));
    await pumpCliente(
      tester,
      repo: MockClienteRepository(clock: clock, initialState: seededState()),
      clock: clock,
      clientCode: joaoCode,
      location: '/horarios',
    );
    expect(find.byKey(const ValueKey('cancel-$joaoNext')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-closed-$joaoNext')), findsNothing);
  });

  testWidgets('CT-04-04 com 1h59 o botão some e aparece o aviso', (
    tester,
  ) async {
    final clock = FixedClock(sp('2026-10-08T08:01:00'));
    await pumpCliente(
      tester,
      repo: MockClienteRepository(clock: clock, initialState: seededState()),
      clock: clock,
      clientCode: joaoCode,
      location: '/horarios',
    );
    expect(find.byKey(const ValueKey('cancel-$joaoNext')), findsNothing);
    expect(
      find.byKey(const ValueKey('cancel-closed-$joaoNext')),
      findsOneWidget,
    );
    expect(
      find.textContaining('cancelamento só com a barbearia'),
      findsOneWidget,
    );
  });

  testWidgets('o botão some quando passa o prazo com a tela aberta e o '
      'repositório recusa', (tester) async {
    final clock = FixedClock(sp('2026-10-08T07:59:00'));
    final repo = MockClienteRepository(
      clock: clock,
      initialState: seededState(),
    );
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      clientCode: joaoCode,
      location: '/horarios',
    );
    await tester.tap(find.byKey(const ValueKey('cancel-$joaoNext')));
    await tester.pumpAndSettle();
    clock.set(
      sp('2026-10-08T08:00:01'),
    ); // passou do prazo com o diálogo aberto
    await tester.tap(find.byKey(const ValueKey('cancel-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Faltam menos de 2 horas'), findsWidgets);
    expect(find.byKey(const ValueKey('cancel-$joaoNext')), findsNothing);
    final s = await repo.state;
    expect(
      s.bookings.firstWhere((x) => x.id == joaoNext).status,
      BookingStatus.scheduled,
    );
  });

  testWidgets('sem código no aparelho: estado vazio', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: '/horarios',
    );
    expect(find.text('Nenhum horário marcado'), findsOneWidget);
    expect(find.text(MockSeed.navalha.name), findsNothing);
  });
}
