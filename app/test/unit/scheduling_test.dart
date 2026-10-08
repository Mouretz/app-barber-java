import 'package:cortaaqui/core/time/sao_paulo.dart';
import 'package:cortaaqui/data/models/availability.dart';
import 'package:cortaaqui/data/models/barbershop.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/domain/scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hora de Brasília -> instante.
DateTime sp(String local) => DateTime.parse('$local-03:00').toUtc();

final expediente = [WorkWindow.hm('08:00', '19:00')];
const day = SpDate(2026, 10, 7);

List<String> starts(List<AvailabilitySlot> slots) =>
    slots.map((s) => formatHm(s.startAt)).toList();

List<AvailabilitySlot> livres({
  required String agora,
  SpDate date = day,
  int duracao = 30,
  List<WorkWindow>? janelas,
  List<TimeSpan> ocupado = const [],
}) => computeFreeSlots(
  date: date,
  now: sp(agora),
  durationMinutes: duracao,
  windows: janelas ?? expediente,
  busy: ocupado,
);

Booking booking(
  String start,
  int minutes, {
  BookingStatus status = BookingStatus.scheduled,
  BookingSource source = BookingSource.clientApp,
}) {
  final s = sp(start);
  return Booking(
    id: 'b-$start',
    barbershopId: 'shop',
    status: status,
    source: source,
    startAt: s,
    endAt: s.add(Duration(minutes: minutes)),
    service: const BookingServiceRef(id: 'svc', name: 'Corte'),
    professional: const ProfessionalPublic(id: 'p1', name: 'P1'),
    client: const BookingClientRef(id: 'c1', name: 'C1'),
    priceCents: 4000,
    createdAt: s.subtract(const Duration(days: 1)),
  );
}

void main() {
  group('horários livres: antecedência de 30 min', () {
    test('CT-01-02 agora 09:30:00, 10:00 aparece (exatamente 30 min)', () {
      expect(starts(livres(agora: '2026-10-07T09:30:00')).first, '10:00');
    });

    test('CT-01-03 agora 09:31:00, o primeiro livre é 10:30', () {
      expect(starts(livres(agora: '2026-10-07T09:31:00')).first, '10:30');
    });

    test('CT-01-04 conta segundos: 09:30:01 não deixa marcar 10:00', () {
      expect(
        hasMinLead(sp('2026-10-07T10:00:00'), sp('2026-10-07T09:30:01')),
        isFalse,
      );
      expect(
        hasMinLead(sp('2026-10-07T10:00:00'), sp('2026-10-07T09:30:00')),
        isTrue,
      );
    });

    test('CT-01-15 horário que já passou não aparece', () {
      final s = starts(livres(agora: '2026-10-07T11:00:00'));
      expect(s, isNot(contains('10:00')));
      expect(s.first, '11:30');
    });
  });

  group('horários livres: expediente e grade', () {
    test('CT-01-05 o primeiro horário é 08:00, não existe 07:30', () {
      final s = starts(livres(agora: '2026-10-06T20:00:00'));
      expect(s.first, '08:00');
      expect(s, isNot(contains('07:30')));
    });

    test('CT-01-06 todos começam em :00 ou :30', () {
      final slots = livres(agora: '2026-10-06T20:00:00');
      expect(slots, hasLength(22)); // 08:00 até 18:30
      for (final s in slots) {
        expect(isOnGrid(s.startAt), isTrue);
      }
      expect(isOnGrid(sp('2026-10-07T10:15:00')), isFalse);
    });

    test('CT-01-07 Corte: 18:30 é o último (termina 19:00), 19:00 não', () {
      final s = starts(livres(agora: '2026-10-06T20:00:00'));
      expect(s.last, '18:30');
      expect(s, isNot(contains('19:00')));
      expect(
        fitsWorkingHours(sp('2026-10-07T18:30:00'), 30, expediente),
        isTrue,
      );
      expect(
        fitsWorkingHours(sp('2026-10-07T19:00:00'), 30, expediente),
        isFalse,
      );
    });

    test('CT-01-08 Combo: 18:00 é o último, 18:30 não cabe', () {
      final s = starts(livres(agora: '2026-10-06T20:00:00', duracao: 60));
      expect(s.last, '18:00');
      expect(s, isNot(contains('18:30')));
      expect(
        fitsWorkingHours(sp('2026-10-07T18:30:00'), 60, expediente),
        isFalse,
      );
    });

    test('CT-01-09 07:30 está antes do expediente', () {
      expect(
        fitsWorkingHours(sp('2026-10-07T07:30:00'), 30, expediente),
        isFalse,
      );
    });

    test('Combo não atravessa o intervalo de almoço', () {
      final s = starts(
        livres(
          agora: '2026-10-06T20:00:00',
          duracao: 60,
          janelas: [
            WorkWindow.hm('10:00', '14:00'),
            WorkWindow.hm('15:00', '21:00'),
          ],
        ),
      );
      expect(s, contains('13:00'));
      expect(s, isNot(contains('13:30')));
      expect(s, isNot(contains('14:00')));
      expect(s, contains('15:00'));
      expect(s.last, '20:00');
    });

    test(
      'janela que começa fora da grade segue o relógio (08:15 -> 08:30)',
      () {
        final s = starts(
          livres(
            agora: '2026-10-06T20:00:00',
            janelas: [WorkWindow.hm('08:15', '10:00')],
          ),
        );
        expect(s, ['08:30', '09:00', '09:30']);
      },
    );

    test('dia sem expediente (folga fixa) não tem horário', () {
      expect(livres(agora: '2026-10-06T20:00:00', janelas: const []), isEmpty);
    });
  });

  group('horários livres: o que ocupa a agenda', () {
    final corte1030 = booking('2026-10-07T10:30:00', 30);

    test(
      'CT-01-10 Corte 10:30 ocupado: 10:00 serve para Corte, não para Combo',
      () {
        final busy = busySpans(bookings: [corte1030]);
        expect(
          starts(livres(agora: '2026-10-06T20:00:00', ocupado: busy)),
          contains('10:00'),
        );
        expect(
          starts(
            livres(agora: '2026-10-06T20:00:00', duracao: 60, ocupado: busy),
          ),
          isNot(contains('10:00')),
        );
      },
    );

    test('CT-01-11 bloqueio ocupa igual a um agendamento', () {
      final block = TimeSpan(
        sp('2026-10-07T10:30:00'),
        sp('2026-10-07T11:00:00'),
      );
      final busy = busySpans(bookings: const [], blocks: [block]);
      final combo = starts(
        livres(agora: '2026-10-06T20:00:00', duracao: 60, ocupado: busy),
      );
      expect(combo, isNot(contains('10:00')));
      expect(combo, isNot(contains('10:30')));
    });

    test(
      'CT-01-12 Corte 10:00: 09:30 some para Combo; 09:00 e 10:30 ficam',
      () {
        final busy = busySpans(bookings: [booking('2026-10-07T10:00:00', 30)]);
        final combo = starts(
          livres(agora: '2026-10-06T20:00:00', duracao: 60, ocupado: busy),
        );
        expect(combo, isNot(contains('09:30')));
        expect(combo, isNot(contains('10:00')));
        expect(combo, containsAll(['09:00', '10:30']));
      },
    );

    test('CT-03-04 encostado não bate ([início, fim))', () {
      final busy = busySpans(bookings: [booking('2026-10-07T10:00:00', 30)]);
      final s = starts(livres(agora: '2026-10-06T20:00:00', ocupado: busy));
      expect(s, containsAll(['09:30', '10:30']));
      expect(s, isNot(contains('10:00')));
    });

    test('CT-03-06 / CT-03-10 falta e cancelado liberam; concluído ocupa', () {
      for (final st in BookingStatus.values) {
        final busy = busySpans(
          bookings: [booking('2026-10-07T10:00:00', 30, status: st)],
        );
        final has1000 = starts(
          livres(agora: '2026-10-06T20:00:00', ocupado: busy),
        ).contains('10:00');
        final shouldBeFree =
            st == BookingStatus.noShow || st == BookingStatus.canceled;
        expect(has1000, shouldBeFree, reason: st.wire);
      }
    });
  });

  group('janela de 14 dias', () {
    final now = sp('2026-10-07T09:00:00');

    test('CT-01-13 hoje + 13 (20/10) tem livres', () {
      expect(isWithinHorizon(const SpDate(2026, 10, 20), now), isTrue);
      expect(
        livres(agora: '2026-10-07T09:00:00', date: const SpDate(2026, 10, 20)),
        isNotEmpty,
      );
    });

    test('CT-01-14 hoje + 14 (21/10) vem vazio', () {
      expect(isWithinHorizon(const SpDate(2026, 10, 21), now), isFalse);
      expect(
        livres(agora: '2026-10-07T09:00:00', date: const SpDate(2026, 10, 21)),
        isEmpty,
      );
    });

    test('ontem vem vazio', () {
      expect(
        livres(agora: '2026-10-07T09:00:00', date: const SpDate(2026, 10, 6)),
        isEmpty,
      );
    });

    test('CT-01-16 o seletor tem 14 dias, de 07/10 a 20/10', () {
      final days = bookableDays(now);
      expect(days, hasLength(14));
      expect(days.first, const SpDate(2026, 10, 7));
      expect(days.last, const SpDate(2026, 10, 20));
    });

    test('CT-00-30 "hoje" é o dia de São Paulo, não o de UTC', () {
      // 07/10 02:30 UTC = 06/10 23:30 em Brasília.
      final late = DateTime.utc(2026, 10, 7, 2, 30);
      expect(SpDate.of(late), const SpDate(2026, 10, 6));
      expect(bookableDays(late).last, const SpDate(2026, 10, 19));
      expect(isWithinHorizon(const SpDate(2026, 10, 20), late), isFalse);
    });
  });

  group('turnos (só filtro de tela)', () {
    test('CT-01-17 12:00 é tarde e 18:00 é noite', () {
      expect(Period.ofMinute(8 * 60), Period.morning);
      expect(Period.ofMinute(11 * 60 + 30), Period.morning);
      expect(Period.ofMinute(12 * 60), Period.afternoon);
      expect(Period.ofMinute(17 * 60 + 30), Period.afternoon);
      expect(Period.ofMinute(18 * 60), Period.evening);
      expect(Period.ofMinute(20 * 60 + 30), Period.evening);
    });
  });

  group('cancelamento até 2h antes', () {
    final b = booking('2026-10-07T10:00:00', 30);

    test('CT-04-02 exatamente 2h antes ainda pode', () {
      expect(clientCanCancel(b, sp('2026-10-07T08:00:00')), isTrue);
    });

    test('CT-04-03 2h menos 1 segundo não pode', () {
      expect(clientCanCancel(b, sp('2026-10-07T08:00:01')), isFalse);
    });

    test('só agendado pode ser cancelado', () {
      for (final st in [
        BookingStatus.completed,
        BookingStatus.noShow,
        BookingStatus.canceled,
      ]) {
        expect(
          clientCanCancel(
            booking('2026-10-07T10:00:00', 30, status: st),
            sp('2026-10-07T06:00:00'),
          ),
          isFalse,
        );
      }
    });
  });

  group('o que conta no limite de 2', () {
    final now = sp('2026-10-07T09:00:00');

    test('só futuro, agendado e marcado pelo app', () {
      expect(
        countsForClientLimit(booking('2026-10-08T10:00:00', 30), now),
        isTrue,
      );
      expect(
        countsForClientLimit(
          booking('2026-10-08T10:00:00', 30, source: BookingSource.staff),
          now,
        ),
        isFalse,
      );
      expect(
        countsForClientLimit(
          booking('2026-10-08T10:00:00', 30, source: BookingSource.counter),
          now,
        ),
        isFalse,
      );
      expect(
        countsForClientLimit(
          booking('2026-10-08T10:00:00', 30, status: BookingStatus.canceled),
          now,
        ),
        isFalse,
      );
      expect(
        countsForClientLimit(booking('2026-10-06T10:00:00', 30), now),
        isFalse,
      );
    });
  });

  test('ISO com offset de Brasília (CT-00-31)', () {
    final i = sp('2026-10-07T09:00:00');
    expect(i, DateTime.utc(2026, 10, 7, 12));
    expect(toIsoSp(i), '2026-10-07T09:00:00-03:00');
    expect(parseInstant('2026-10-07T09:00:00-03:00'), i);
  });
}
