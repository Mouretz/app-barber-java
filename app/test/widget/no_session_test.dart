import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/data/repositories/cliente_repository.dart';
import 'package:cortaaqui/presentation/cliente/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// Repositório espião: conta as chamadas de `listMyBookings`.
class SpyRepo extends MockClienteRepository {
  SpyRepo(Clock clock) : super(clock: clock, initialState: seededState());

  final List<String> listCalls = [];

  @override
  Future<List<Booking>> listMyBookings({
    required String clientCode,
    BookingScope scope = BookingScope.upcoming,
    int limit = 20,
  }) {
    listCalls.add(clientCode);
    return super.listMyBookings(
      clientCode: clientCode,
      scope: scope,
      limit: limit,
    );
  }
}

void expectNoError() {
  expect(find.byType(ErrorBox), findsNothing);
  expect(find.text('Tentar de novo'), findsNothing);
}

void main() {
  testWidgets('aparelho sem código: Início não chama listMyBookings e mostra '
      '"Você ainda não tem horários"', (tester) async {
    final clock = FixedClock(kNow);
    final repo = SpyRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock);

    expect(find.byKey(const ValueKey('home-empty-next')), findsOneWidget);
    expect(find.text('Você ainda não tem horários'), findsOneWidget);
    expect(find.text('Nenhum horário marcado'), findsNothing);
    expectNoError();
    expect(repo.listCalls, isEmpty);
  });

  testWidgets('aparelho sem código: Horários não chama listMyBookings, nem nos '
      'próximos nem no histórico', (tester) async {
    final clock = FixedClock(kNow);
    final repo = SpyRepo(clock);
    await pumpCliente(tester, repo: repo, clock: clock, location: '/horarios');

    expect(find.text('Você ainda não tem horários'), findsOneWidget);
    expectNoError();

    await tester.tap(find.byKey(const ValueKey('scope-past')));
    await tester.pumpAndSettle();
    expect(find.text('Nada no histórico ainda'), findsOneWidget);
    expectNoError();
    expect(repo.listCalls, isEmpty);
  });

  testWidgets('código liberado (401): limpa a sessão, para de chamar e mostra '
      '"Você ainda não tem horários", sem tela de erro', (tester) async {
    final clock = FixedClock(kNow);
    final repo = SpyRepo(clock);
    await repo.releaseClientDevice(
      barbershopId: MockSeed.shopId,
      clientId: MockSeed.joaoId,
    );
    await pumpCliente(
      tester,
      repo: repo,
      clock: clock,
      clientCode: joaoCode,
      location: '/horarios',
    );

    expect(find.text('Você ainda não tem horários'), findsOneWidget);
    expectNoError();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceStore.kClientCode), isNull);
    expect(repo.listCalls, everyElement(joaoCode));
    final callsAfter401 = repo.listCalls.length;
    expect(callsAfter401, greaterThan(0));

    // Sem sessão, trocar de aba e voltar ao Início não chama mais.
    await tester.tap(find.byKey(const ValueKey('scope-past')));
    await tester.pumpAndSettle();
    expect(find.text('Nada no histórico ainda'), findsOneWidget);
    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    expect(find.text('Você ainda não tem horários'), findsOneWidget);
    expectNoError();
    expect(repo.listCalls, hasLength(callsAfter401));
  });
}
