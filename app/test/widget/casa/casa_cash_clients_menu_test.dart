import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/data/models/staff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'casa_harness.dart';

void main() {
  late FixedClock clock;
  late MockCasaRepository repo;

  setUp(() {
    clock = FixedClock(kCasaNow);
    repo = casaRepo(clock);
  });

  Future<String> token(String email) async => (await repo.login(
    email: email,
    password: MockCasaSeed.mockPassword,
  )).accessToken;

  /// Conclui os 2 horários do Caio de quinta (João Corte R$ 40 e Rafael
  /// Corte + Barba R$ 60) com 60/40.
  Future<void> completeCaio() async {
    clock.set(sp('2026-10-08T13:00:00'));
    final g = await token(MockCasaSeed.marinaEmail);
    for (final id in [
      '6f1c2a10-0000-4000-8000-0000000000d1',
      '6f1c2a10-0000-4000-8000-0000000000d4',
    ]) {
      await repo.changeBookingStatus(
        g,
        barbershopId: MockSeed.shopId,
        bookingId: id,
        idempotencyKey: 'k-$id',
        status: BookingStatus.completed,
      );
    }
  }

  group('caixa', () {
    testWidgets('CT-08-15 gerente: "Caixa da casa" com a parte da casa e as '
        'linhas de todos', (tester) async {
      await completeCaio();
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.marinaEmail,
      );
      await openTab(tester, 'Caixa');
      expect(find.text('Caixa da casa'), findsOneWidget);
      expect(find.text('Meus ganhos'), findsNothing);
      final totals = find.byKey(const ValueKey('cash-totals'));
      expect(
        find.descendant(of: totals, matching: find.text('Casa')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cash-row-${MockSeed.caioId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cash-row-${MockSeed.helenaId}')),
        findsOneWidget,
      );
    });

    testWidgets('CT-08-09/13 profissional: "Meus ganhos", só a linha dele e '
        'nunca a parte da casa', (tester) async {
      await completeCaio();
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      await openTab(tester, 'Caixa');
      expect(find.text('Meus ganhos'), findsOneWidget);
      expect(find.text('Casa'), findsNothing);
      expect(find.text('R\$ 40,00'), findsNothing);
      expect(
        find.byKey(const ValueKey('cash-row-${MockSeed.helenaId}')),
        findsNothing,
      );
    });
  });

  group('clientes', () {
    Future<void> openJoao(WidgetTester tester) async {
      await openTab(tester, 'Clientes');
      await tester.enterText(
        find.byKey(const ValueKey('client-search')),
        'joao',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('client-${MockSeed.joaoId}')));
      await tester.pumpAndSettle();
    }

    testWidgets('profissional abre a ficha mas não vê Editar nem Liberar '
        'aparelho', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      await openJoao(tester);
      expect(find.text('João Almeida'), findsOneWidget);
      expect(find.byKey(const ValueKey('client-edit')), findsNothing);
      expect(find.byKey(const ValueKey('client-release')), findsNothing);
    });

    testWidgets('gerente libera o aparelho e o botão some (hasDevice false)', (
      tester,
    ) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.marinaEmail,
      );
      await openJoao(tester);
      expect(find.byKey(const ValueKey('client-edit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('client-release')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aparelho liberado'), findsOneWidget);
      expect(find.byKey(const ValueKey('client-release')), findsNothing);
      expect(
        (await repo.state).revokedCodes,
        contains(MockSeed.joaoDeviceCode),
      );
    });

    testWidgets('DEVICE_RELEASE_NOT_ALLOWED vira mensagem clara (Rafael só '
        'tem horário da Casa)', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.marinaEmail,
      );
      await openTab(tester, 'Clientes');
      await tester.enterText(
        find.byKey(const ValueKey('client-search')),
        'rafael',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('client-${MockSeed.rafaelId}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('client-release')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Só dá pra liberar o aparelho de quem já agendou pelo app nesta barbearia.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ficha de balcão sem telefone mostra "Sem telefone"', (
      tester,
    ) async {
      final c = await token(MockCasaSeed.caioEmail);
      await repo.createStaffBooking(
        c,
        barbershopId: MockSeed.shopId,
        idempotencyKey: 'b1',
        request: StaffBookingRequest(
          serviceId: MockSeed.corteId,
          professionalId: MockSeed.caioId,
          startAt: SpDateX.thu.at(9 * 60),
          source: BookingSource.counter,
          newClientName: 'Zeca Balcão',
        ),
      );
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      await openTab(tester, 'Clientes');
      await tester.enterText(
        find.byKey(const ValueKey('client-search')),
        'zeca',
      );
      await tester.pumpAndSettle();
      expect(find.text('Sem telefone'), findsOneWidget);
    });

    testWidgets('CT-17-06 cadastrar e ver na busca sem reabrir', (
      tester,
    ) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      await openTab(tester, 'Clientes');
      await tester.tap(find.byKey(const ValueKey('client-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-client-name')),
        'Ana Lima',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-client-phone')),
        '(11) 91234-0000',
      );
      await tester.tap(find.byKey(const ValueKey('new-client-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ana Lima'), findsOneWidget);
    });
  });

  group('menu e papéis', () {
    testWidgets('profissional não vê Gerência', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      await openTab(tester, 'Menu');
      expect(find.text('Gerência'.toUpperCase()), findsNothing);
      expect(find.byKey(const ValueKey('menu-team')), findsNothing);
      expect(find.byKey(const ValueKey('menu-commission')), findsNothing);
    });

    testWidgets('Equipe lista inativos; gerente que se desativa como '
        'profissional continua gerente e sem agenda própria', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.helenaEmail,
      );
      await openTab(tester, 'Menu');
      expect(
        find.text('Gerente e Profissional · Barbearia Navalha'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('menu-team')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('team-active-${MockSeed.helenaId}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('team-status-${MockSeed.helenaId}')),
            )
            .data,
        'Desativado',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Gerente · Barbearia Navalha'), findsOneWidget);
      await openTab(tester, 'Agenda');
      expect(find.text('Agenda da casa'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pro-${MockSeed.helenaId}')),
        findsNothing,
      );
    });

    testWidgets('desativar com horário futuro mostra o motivo', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.marinaEmail,
      );
      await openTab(tester, 'Menu');
      await tester.tap(find.byKey(const ValueKey('menu-team')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('team-active-${MockSeed.caioId}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Esse profissional tem horários marcados. Cancele antes de desativar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Sair volta pro login', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.caioEmail,
      );
      await openTab(tester, 'Menu');
      await tester.tap(find.byKey(const ValueKey('menu-logout')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    });

    testWidgets('CT-20-03 % decimal é recusada na tela', (tester) async {
      await pumpCasa(
        tester,
        repo: repo,
        clock: clock,
        email: MockCasaSeed.marinaEmail,
      );
      await openTab(tester, 'Menu');
      await tester.tap(find.byKey(const ValueKey('menu-commission')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('commission-default')),
        '60.5',
      );
      await tester.tap(find.byKey(const ValueKey('commission-save')));
      await tester.pumpAndSettle();
      expect(find.text('Use números inteiros de 0 a 100.'), findsOneWidget);
    });
  });
}
