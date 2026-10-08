import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import 'mock_state.dart';

/// Seed oficial do modo mock (plano da QA, seção 5 e CT-00-33): Barbearia
/// Navalha, 2 profissionais, os serviços Corte 30, Barba 30 e Corte + Barba 60,
/// e 1 cliente (mais um segundo cliente só para ocupar a agenda).
///
/// Os ids são fixos para o seed do servidor poder usar os mesmos.
abstract final class MockSeed {
  static const shopId = '6f1c2a10-0000-4000-8000-000000000001';

  static const corteId = '6f1c2a10-0000-4000-8000-0000000000a1';
  static const barbaId = '6f1c2a10-0000-4000-8000-0000000000a2';
  static const comboId = '6f1c2a10-0000-4000-8000-0000000000a3';

  static const caioId = '6f1c2a10-0000-4000-8000-0000000000b1';
  static const helenaId = '6f1c2a10-0000-4000-8000-0000000000b2';

  static const joaoId = '6f1c2a10-0000-4000-8000-0000000000c1';
  static const joaoPhone = '5511987654321';
  static const rafaelId = '6f1c2a10-0000-4000-8000-0000000000c2';
  static const rafaelPhone = '5521912345678';

  static const corte = Service(
    id: corteId,
    name: 'Corte',
    durationMinutes: 30,
    priceCents: 4000,
    active: true,
  );
  static const barba = Service(
    id: barbaId,
    name: 'Barba',
    durationMinutes: 30,
    priceCents: 3000,
    active: true,
  );
  static const combo = Service(
    id: comboId,
    name: 'Corte + Barba',
    durationMinutes: 60,
    priceCents: 6000,
    active: true,
  );

  static const caio = ProfessionalPublic(id: caioId, name: 'Caio');
  static const helena = ProfessionalPublic(id: helenaId, name: 'Helena');

  static const navalha = BarbershopDetail(
    id: shopId,
    name: 'Barbearia Navalha',
    neighborhood: 'Pinheiros',
    city: 'São Paulo',
    startingPriceCents: 3000,
    address: 'Rua dos Pinheiros, 1000 · Pinheiros, São Paulo',
    phone: '1130000000',
    services: [corte, barba, combo],
    professionals: [caio, helena],
  );

  /// Caio: segunda a sábado, 08:00–19:00. Helena: terça a domingo, 10:00–14:00
  /// e 15:00–21:00 (almoço no meio).
  static final Map<String, Map<int, List<WorkWindow>>> weeklyHours = {
    caioId: {
      for (var d = 1; d <= 6; d++) d: [WorkWindow.hm('08:00', '19:00')],
    },
    helenaId: {
      for (var d = 2; d <= 7; d++)
        d: [WorkWindow.hm('10:00', '14:00'), WorkWindow.hm('15:00', '21:00')],
    },
  };

  static List<MockShop> shops() => [
    MockShop(detail: navalha, weeklyHours: weeklyHours),
  ];

  /// Estado inicial, montado em volta de [now] para o APK sempre abrir com
  /// horários no futuro e histórico no passado.
  static MockState build(DateTime now) {
    final today = SpDate.of(now);
    // Próximo dia (a partir de amanhã) em que o Caio atende.
    var day = today.addDays(1);
    while (day.weekday == 7) {
      day = day.addDays(1);
    }

    Booking booking({
      required String id,
      required ProfessionalPublic pro,
      required Service svc,
      required DateTime start,
      required String clientId,
      required String clientName,
      required BookingSource source,
      BookingStatus status = BookingStatus.scheduled,
      CanceledBy? canceledBy,
    }) {
      return Booking(
        id: id,
        barbershopId: shopId,
        barbershopName: navalha.name,
        status: status,
        source: source,
        startAt: start,
        endAt: start.add(Duration(minutes: svc.durationMinutes)),
        service: BookingServiceRef(id: svc.id, name: svc.name),
        professional: pro,
        client: BookingClientRef(id: clientId, name: clientName),
        priceCents: svc.priceCents,
        canceledBy: canceledBy,
        createdAt: start.subtract(const Duration(days: 2)),
      );
    }

    final created = today.addDays(-30).at(9 * 60);
    return MockState(
      shops: shops(),
      clients: [
        MockClient(
          id: joaoId,
          phone: joaoPhone,
          name: 'João Almeida',
          createdAt: created,
          fichaNames: {shopId: 'João Almeida'},
        ),
        MockClient(
          id: rafaelId,
          phone: rafaelPhone,
          name: 'Rafael Souza',
          createdAt: created,
          fichaNames: {shopId: 'Rafael Souza'},
        ),
      ],
      bookings: [
        // João: 1 futuro pelo app e 2 no histórico.
        booking(
          id: '6f1c2a10-0000-4000-8000-0000000000d1',
          pro: caio,
          svc: corte,
          start: day.at(10 * 60),
          clientId: joaoId,
          clientName: 'João Almeida',
          source: BookingSource.clientApp,
        ),
        booking(
          id: '6f1c2a10-0000-4000-8000-0000000000d2',
          pro: helena,
          svc: combo,
          start: today.addDays(-7).at(15 * 60),
          clientId: joaoId,
          clientName: 'João Almeida',
          source: BookingSource.clientApp,
          status: BookingStatus.completed,
        ),
        booking(
          id: '6f1c2a10-0000-4000-8000-0000000000d3',
          pro: caio,
          svc: barba,
          start: today.addDays(-3).at(11 * 60),
          clientId: joaoId,
          clientName: 'João Almeida',
          source: BookingSource.clientApp,
          status: BookingStatus.canceled,
          canceledBy: CanceledBy.staff,
        ),
        // Rafael: marcado pela Casa, ocupa a agenda do Caio no mesmo dia.
        booking(
          id: '6f1c2a10-0000-4000-8000-0000000000d4',
          pro: caio,
          svc: combo,
          start: day.at(11 * 60),
          clientId: rafaelId,
          clientName: 'Rafael Souza',
          source: BookingSource.staff,
        ),
      ],
      blocks: [
        MockBlock(
          id: '6f1c2a10-0000-4000-8000-0000000000e1',
          barbershopId: shopId,
          professionalId: caioId,
          startAt: day.at(14 * 60),
          endAt: day.at(15 * 60),
        ),
      ],
    );
  }
}
