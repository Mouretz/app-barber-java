import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/core/time/sao_paulo.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_persistence.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/mock/mock_state.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/data/repositories/cliente_repository.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime sp(String local) => DateTime.parse('$local-03:00').toUtc();

const shop = MockSeed.shopId;
const caio = MockSeed.caioId;
const helena = MockSeed.helenaId;
const corte = MockSeed.corteId;
const combo = MockSeed.comboId;

Matcher problem(ErrorCode code) =>
    isA<ApiProblem>().having((p) => p.code, 'code', code);

void main() {
  late FixedClock clock;
  late MockClienteRepository repo;
  var key = 0;
  String nextKey() => 'k-${key++}';

  /// Agenda limpa (sem o seed de agendamentos), agora = quarta 07/10 09:00.
  setUp(() {
    clock = FixedClock(sp('2026-10-07T09:00:00'));
    repo = MockClienteRepository(
      clock: clock,
      initialState: MockState(shops: MockSeed.shops()),
    );
  });

  Future<ClientBookingCreated> book(
    String start, {
    String service = corte,
    String pro = caio,
    String? code,
    String phone = '(11) 98765-4321',
    String name = 'Cliente Um',
    String? idem,
  }) => repo.createClientBooking(
    barbershopId: shop,
    idempotencyKey: idem ?? nextKey(),
    clientCode: code,
    request: ClientBookingRequest(
      serviceId: service,
      professionalId: pro,
      startAt: sp(start),
      client: code == null ? ClientInfo(name: name, phone: phone) : null,
    ),
  );

  group('agendar (história 1)', () {
    test(
      'CT-01-01 cria agendado com preço gravado e devolve o código',
      () async {
        final r = await book('2026-10-07T10:00:00');
        expect(r.clientCode, isNotNull);
        expect(r.booking.status, BookingStatus.scheduled);
        expect(r.booking.source, BookingSource.clientApp);
        expect(r.booking.barbershopId, shop);
        expect(r.booking.professional.id, caio);
        expect(r.booking.priceCents, 4000);
        expect(r.booking.endAt, sp('2026-10-07T10:30:00'));
        expect(
          r.booking.client.phone,
          isNull,
          reason: 'cliente não vê telefone',
        );
      },
    );

    test(
      'com o código, não manda nome e telefone e não recebe código de novo',
      () async {
        final first = await book('2026-10-07T10:00:00');
        final second = await book(
          '2026-10-08T10:00:00',
          code: first.clientCode,
        );
        expect(second.clientCode, isNull);
        expect(second.booking.client.id, first.booking.client.id);
      },
    );

    test(
      'CT-01-02 / CT-01-03 antecedência: 30 min aceita, 29 min recusa',
      () async {
        clock.set(sp('2026-10-07T09:30:00'));
        await book('2026-10-07T10:00:00');
        clock.set(sp('2026-10-07T09:31:00'));
        await expectLater(
          book('2026-10-07T10:00:00', pro: helena),
          throwsA(problem(ErrorCode.tooSoon)),
        );
        expect((await repo.state).bookings, hasLength(1));
      },
    );

    test(
      'CT-01-06 fora da grade (10:15): 422 VALIDATION_ERROR no startAt',
      () async {
        await expectLater(
          book('2026-10-07T10:15:00'),
          throwsA(
            isA<ApiProblem>()
                .having((p) => p.code, 'code', ErrorCode.validationError)
                .having((p) => p.status, 'status', 422)
                .having((p) => p.hasField('startAt'), 'campo startAt', isTrue),
          ),
        );
      },
    );

    test('CT-01-07 / CT-01-08 / CT-01-09 expediente', () async {
      await book('2026-10-07T18:30:00');
      await expectLater(
        book('2026-10-07T19:00:00', phone: '21912345678'),
        throwsA(problem(ErrorCode.outsideWorkingHours)),
      );
      await expectLater(
        book('2026-10-08T18:30:00', service: combo, phone: '21912345678'),
        throwsA(problem(ErrorCode.outsideWorkingHours)),
      );
      await book('2026-10-08T18:00:00', service: combo, phone: '21912345678');
      await expectLater(
        book('2026-10-09T07:30:00', phone: '31912345678'),
        throwsA(problem(ErrorCode.outsideWorkingHours)),
      );
    });

    test('CT-01-10 / CT-03-02 Combo sobre um Corte é conflito', () async {
      await book('2026-10-07T10:30:00');
      await expectLater(
        book('2026-10-07T10:00:00', service: combo, phone: '21912345678'),
        throwsA(problem(ErrorCode.slotTaken)),
      );
    });

    test('CT-01-11 bloqueio ocupa', () async {
      (await repo.state).blocks.add(
        MockBlock(
          id: 'blk',
          barbershopId: shop,
          professionalId: caio,
          startAt: sp('2026-10-07T10:30:00'),
          endAt: sp('2026-10-07T11:00:00'),
        ),
      );
      await expectLater(
        book('2026-10-07T10:00:00', service: combo),
        throwsA(problem(ErrorCode.slotTaken)),
      );
      final av = await repo.getAvailability(
        barbershopId: shop,
        serviceId: combo,
        professionalId: caio,
        date: const SpDate(2026, 10, 7),
      );
      expect(
        av.slots.map((s) => formatHm(s.startAt)),
        isNot(contains('10:00')),
      );
    });

    test('CT-03-05 a regra é por profissional', () async {
      await book('2026-10-07T11:00:00');
      await book('2026-10-07T11:00:00', pro: helena, phone: '21912345678');
    });

    test('CT-01-13 / CT-01-14 janela de 14 dias', () async {
      await book('2026-10-20T10:00:00');
      await expectLater(
        book('2026-10-21T10:00:00', phone: '21912345678'),
        throwsA(problem(ErrorCode.dateOutOfRange)),
      );
      await expectLater(
        repo.getAvailability(
          barbershopId: shop,
          serviceId: corte,
          professionalId: caio,
          date: const SpDate(2026, 10, 21),
        ),
        throwsA(problem(ErrorCode.dateOutOfRange)),
      );
    });

    test('CT-01-15 horário que já passou é recusado', () async {
      clock.set(sp('2026-10-07T11:00:00'));
      await expectLater(
        book('2026-10-07T10:00:00'),
        throwsA(problem(ErrorCode.tooSoon)),
      );
    });

    test('CT-01-23 serviço ou profissional de fora da barbearia', () async {
      await expectLater(
        book('2026-10-07T10:00:00', service: 'outro'),
        throwsA(problem(ErrorCode.notFound)),
      );
      await expectLater(
        book('2026-10-07T10:00:00', pro: 'outro'),
        throwsA(problem(ErrorCode.notFound)),
      );
    });

    test(
      'CT-17-12 telefone inválido e nome curto voltam com o campo',
      () async {
        await expectLater(
          book('2026-10-07T10:00:00', phone: '987654321'),
          throwsA(
            isA<ApiProblem>()
                .having((p) => p.code, 'code', ErrorCode.validationError)
                .having((p) => p.hasField('phone'), 'phone', isTrue),
          ),
        );
        await expectLater(
          book('2026-10-07T10:00:00', name: 'J'),
          throwsA(
            isA<ApiProblem>().having((p) => p.hasField('name'), 'name', isTrue),
          ),
        );
        expect((await repo.state).bookings, isEmpty);
      },
    );

    test('código inválido é 401', () async {
      await expectLater(
        book('2026-10-07T10:00:00', code: 'nao-existe'),
        throwsA(problem(ErrorCode.unauthorized)),
      );
    });
  });

  group('limite de 2 horários futuros pelo app', () {
    test('CT-01-19 o 3º é recusado', () async {
      await book('2026-10-08T10:00:00');
      await book('2026-10-09T10:00:00');
      await expectLater(
        book('2026-10-10T10:00:00'),
        throwsA(problem(ErrorCode.bookingLimitReached)),
      );
    });

    test('CT-01-20 cancelado não conta', () async {
      final a = await book('2026-10-08T10:00:00');
      await book('2026-10-09T10:00:00');
      await repo.cancelMyBooking(
        clientCode: a.clientCode!,
        bookingId: a.booking.id,
      );
      await book('2026-10-10T10:00:00');
    });

    test('CT-01-21 passado e status final não contam', () async {
      final s = await repo.state;
      final first = await book('2026-10-07T10:00:00');
      // Vira passado e ganha um status final.
      final i = s.bookings.indexWhere((b) => b.id == first.booking.id);
      s.bookings[i] = s.bookings[i].copyWith(status: BookingStatus.completed);
      await book('2026-10-08T10:00:00');
      await book('2026-10-09T10:00:00');
      await expectLater(
        book('2026-10-10T10:00:00'),
        throwsA(problem(ErrorCode.bookingLimitReached)),
      );
    });

    test('CT-01-29 o limite soma as variações do mesmo número', () async {
      await book('2026-10-08T10:00:00', phone: '(11) 98765-4321');
      final second = await book('2026-10-09T10:00:00', phone: '5511987654321');
      await expectLater(
        book('2026-10-10T10:00:00', phone: '+55 11 98765-4321'),
        throwsA(problem(ErrorCode.bookingLimitReached)),
      );
      final s = await repo.state;
      expect(s.clients, hasLength(1));
      expect(
        s.bookings.every((b) => b.client.id == second.booking.client.id),
        isTrue,
      );
    });

    test('o que a Casa marca não conta no limite', () async {
      final seed = MockSeed.build(clock.now());
      repo = MockClienteRepository(clock: clock, initialState: seed);
      // João tem 1 futuro pelo app no seed; o do Rafael é da Casa.
      await book('2026-10-12T10:00:00', phone: '21912345678');
      await book('2026-10-13T10:00:00', phone: '21912345678');
      await book('2026-10-14T10:00:00', phone: '11987654321');
      await expectLater(
        book('2026-10-15T10:00:00', phone: '11987654321'),
        throwsA(problem(ErrorCode.bookingLimitReached)),
      );
    });
  });

  group('pedido repetido (Idempotency-Key)', () {
    test(
      'CT-00-04 mesma chave 2 vezes: 1 agendamento, mesmo id e código',
      () async {
        final a = await book('2026-10-07T10:00:00', idem: 'mesma');
        final b = await book('2026-10-07T10:00:00', idem: 'mesma');
        expect(b.booking.id, a.booking.id);
        expect(b.clientCode, a.clientCode);
        expect((await repo.state).bookings, hasLength(1));
      },
    );

    test('CT-00-05 toque duplo ao mesmo tempo: 1 agendamento', () async {
      repo = MockClienteRepository(
        clock: clock,
        initialState: MockState(shops: MockSeed.shops()),
        latency: const Duration(milliseconds: 5),
      );
      final r = await Future.wait([
        book('2026-10-07T10:00:00', idem: 'duplo'),
        book('2026-10-07T10:00:00', idem: 'duplo'),
      ]);
      expect(r[0].booking.id, r[1].booking.id);
      expect((await repo.state).bookings, hasLength(1));
    });

    test('CT-00-04 a repetição conta 1 no limite', () async {
      await book('2026-10-08T10:00:00', idem: 'x');
      await book('2026-10-08T10:00:00', idem: 'x');
      await book('2026-10-09T10:00:00');
    });

    test(
      'CT-00-07 chaves diferentes com dados iguais: o 2º é conflito',
      () async {
        await book('2026-10-07T10:00:00');
        await expectLater(
          book('2026-10-07T10:00:00'),
          throwsA(problem(ErrorCode.slotTaken)),
        );
      },
    );

    test('CT-00-08 mesma chave com dados diferentes é recusada', () async {
      await book('2026-10-07T10:00:00', idem: 'z');
      await expectLater(
        book('2026-10-07T11:00:00', idem: 'z'),
        throwsA(problem(ErrorCode.idempotencyKeyReused)),
      );
    });
  });

  group('meus horários e cancelamento (história 4)', () {
    test(
      'CT-04-01 próximos em ordem crescente e histórico decrescente',
      () async {
        final seed = MockSeed.build(clock.now());
        const code = 'codigo-do-joao';
        seed.codes[code] = MockSeed.joaoId;
        repo = MockClienteRepository(clock: clock, initialState: seed);
        await book('2026-10-12T10:00:00', code: code);
        final up = await repo.listMyBookings(clientCode: code);
        expect(up, hasLength(2));
        expect(up.first.startAt.isBefore(up.last.startAt), isTrue);
        final past = await repo.listMyBookings(
          clientCode: code,
          scope: BookingScope.past,
        );
        expect(past, hasLength(2));
        expect(past.first.startAt.isAfter(past.last.startAt), isTrue);
        expect(past.any((b) => b.canceledByShop), isTrue);
      },
    );

    test(
      'CT-04-02 / CT-04-03 cancelar: exatamente 2h pode, 2h - 1s não',
      () async {
        final a = await book('2026-10-07T12:00:00');
        final b = await book(
          '2026-10-07T12:00:00',
          pro: helena,
          code: a.clientCode,
        );
        clock.set(sp('2026-10-07T10:00:00'));
        final ok = await repo.cancelMyBooking(
          clientCode: a.clientCode!,
          bookingId: a.booking.id,
        );
        expect(ok.status, BookingStatus.canceled);
        expect(ok.canceledBy, CanceledBy.client);
        clock.set(sp('2026-10-07T10:00:01'));
        await expectLater(
          repo.cancelMyBooking(
            clientCode: a.clientCode!,
            bookingId: b.booking.id,
          ),
          throwsA(problem(ErrorCode.cancelWindowClosed)),
        );
        final s = await repo.state;
        expect(
          s.bookings.firstWhere((x) => x.id == b.booking.id).status,
          BookingStatus.scheduled,
        );
      },
    );

    test('canCancel vem calculado na lista', () async {
      final a = await book('2026-10-07T12:00:00');
      var list = await repo.listMyBookings(clientCode: a.clientCode!);
      expect(list.single.canCancel, isTrue);
      clock.set(sp('2026-10-07T10:01:00'));
      list = await repo.listMyBookings(clientCode: a.clientCode!);
      expect(list.single.canCancel, isFalse);
    });

    test(
      'CT-04-05 cancelado volta para os livres e outro cliente marca',
      () async {
        final a = await book('2026-10-07T12:00:00');
        await repo.cancelMyBooking(
          clientCode: a.clientCode!,
          bookingId: a.booking.id,
        );
        final av = await repo.getAvailability(
          barbershopId: shop,
          serviceId: corte,
          professionalId: caio,
          date: const SpDate(2026, 10, 7),
        );
        expect(av.slots.map((s) => formatHm(s.startAt)), contains('12:00'));
        await book('2026-10-07T12:00:00', phone: '21912345678');
      },
    );

    test('CT-04-06 código inexistente: 401', () async {
      await expectLater(
        repo.listMyBookings(clientCode: 'nao-existe'),
        throwsA(problem(ErrorCode.unauthorized)),
      );
      await expectLater(
        repo.cancelMyBooking(clientCode: 'nao-existe', bookingId: 'x'),
        throwsA(problem(ErrorCode.unauthorized)),
      );
    });

    test('CT-04-07 não cancela horário de outro cliente', () async {
      final a = await book('2026-10-08T10:00:00');
      final b = await book('2026-10-08T11:00:00', phone: '21912345678');
      await expectLater(
        repo.cancelMyBooking(
          clientCode: b.clientCode!,
          bookingId: a.booking.id,
        ),
        throwsA(problem(ErrorCode.notFound)),
      );
    });

    test(
      'CT-04-10 cancelado pela barbearia: o cliente recebe "status mudou"',
      () async {
        final a = await book('2026-10-08T10:00:00');
        final s = await repo.state;
        final i = s.bookings.indexWhere((x) => x.id == a.booking.id);
        s.bookings[i] = s.bookings[i].copyWith(
          status: BookingStatus.canceled,
          canceledBy: CanceledBy.staff,
        );
        await expectLater(
          repo.cancelMyBooking(
            clientCode: a.clientCode!,
            bookingId: a.booking.id,
          ),
          throwsA(problem(ErrorCode.invalidStatusTransition)),
        );
      },
    );

    test('CT-00-06 cancelar 2 vezes devolve o mesmo resultado', () async {
      final a = await book('2026-10-08T10:00:00');
      final c1 = await repo.cancelMyBooking(
        clientCode: a.clientCode!,
        bookingId: a.booking.id,
      );
      final c2 = await repo.cancelMyBooking(
        clientCode: a.clientCode!,
        bookingId: a.booking.id,
      );
      expect(c2, c1);
    });
  });

  group('CT-04-08 só telefone não basta', () {
    late MockState seed;
    setUp(() {
      seed = MockSeed.build(clock.now());
      repo = MockClienteRepository(clock: clock, initialState: seed);
    });

    test('telefone já cadastrado, aparelho sem código: marca, mas não devolve '
        'código', () async {
      final codesBefore = Map.of(seed.codes);
      final r = await book('2026-10-12T10:00:00', phone: '(11) 98765-4321');
      expect(r.clientCode, isNull);
      expect(seed.codes, codesBefore, reason: 'nenhum código novo');
      final saved = seed.bookings.firstWhere((b) => b.id == r.booking.id);
      expect(saved.client.id, MockSeed.joaoId, reason: 'mesmo cadastro');
      expect(
        seed.clients.where((c) => c.phone == MockSeed.joaoPhone),
        hasLength(1),
      );
    });

    test('qualquer jeito de escrever o número dá o mesmo resultado', () async {
      for (final (i, phone) in [
        '+55 11 98765-4321',
        '5511987654321',
        '+5511987654321',
      ].indexed) {
        // Cada um num repositório novo, para não bater no limite de 2.
        seed = MockSeed.build(clock.now());
        repo = MockClienteRepository(clock: clock, initialState: seed);
        final r = await book('2026-10-1${2 + i}T10:00:00', phone: phone);
        expect(r.clientCode, isNull, reason: phone);
      }
    });

    test('pedido repetido também não devolve código', () async {
      final a = await book('2026-10-12T10:00:00', idem: 'rep');
      final b = await book('2026-10-12T10:00:00', idem: 'rep');
      expect(a.clientCode, isNull);
      expect(b.clientCode, isNull);
      expect(b.booking.id, a.booking.id);
    });

    test('telefone novo recebe o código uma vez só; depois, sem o código, '
        'não recebe de novo', () async {
      final first = await book('2026-10-12T10:00:00', phone: '31998765432');
      expect(first.clientCode, isNotNull);
      final again = await book(
        '2026-10-13T10:00:00',
        phone: '+55 (31) 99876-5432',
      );
      expect(again.clientCode, isNull);
      expect(again.booking.client.id, first.booking.client.id);
    });

    test('o horário marcado sem código conta no limite do telefone', () async {
      // João já tem 1 futuro pelo app no seed.
      await book('2026-10-12T10:00:00', phone: '11987654321');
      await expectLater(
        book('2026-10-13T10:00:00', phone: '(11) 98765-4321'),
        throwsA(problem(ErrorCode.bookingLimitReached)),
      );
    });

    test('listar ou cancelar só com o telefone é recusado', () async {
      for (final phone in [
        MockSeed.joaoPhone,
        '11987654321',
        '(11) 98765-4321',
      ]) {
        await expectLater(
          repo.listMyBookings(clientCode: phone),
          throwsA(problem(ErrorCode.unauthorized)),
        );
        await expectLater(
          repo.cancelMyBooking(
            clientCode: phone,
            bookingId: '6f1c2a10-0000-4000-8000-0000000000d1',
          ),
          throwsA(problem(ErrorCode.unauthorized)),
        );
      }
      expect(
        seed.bookings
            .firstWhere((b) => b.id == '6f1c2a10-0000-4000-8000-0000000000d1')
            .status,
        BookingStatus.scheduled,
      );
    });
  });

  group('telefone no formato +55', () {
    test('o cadastro guarda +55 + DDD + número, venha como vier', () async {
      await book('2026-10-12T10:00:00', phone: '(21) 91234-5678');
      await book('2026-10-13T10:00:00', phone: '5531998765432');
      await book('2026-10-14T10:00:00', phone: '+55 41 3456-7890');
      final s = await repo.state;
      expect(s.clients.map((c) => c.phone), [
        '+5521912345678',
        '+5531998765432',
        '+554134567890',
      ]);
      for (final c in s.clients) {
        expect(c.phone, matches(RegExp(r'^\+55\d{10,11}$')));
      }
    });

    test('o seed usa o mesmo formato', () {
      expect(MockSeed.joaoPhone, '+5511987654321');
      expect(MockSeed.rafaelPhone, '+5521912345678');
    });

    test('a resposta para o app Cliente não leva telefone', () async {
      final r = await book('2026-10-12T10:00:00');
      expect(r.booking.client.phone, isNull);
      final s = await repo.state;
      expect(
        s.bookings.single.client.phone,
        '+5511987654321',
        reason: 'guardado para a casa',
      );
    });
  });

  group('DATE_OUT_OF_RANGE para listar e para marcar', () {
    for (final (nome, dia) in [
      ('ontem (06/10)', '2026-10-06'),
      ('hoje + 14 (21/10)', '2026-10-21'),
    ]) {
      test('$nome: 422 nos dois', () async {
        await expectLater(
          repo.getAvailability(
            barbershopId: shop,
            serviceId: corte,
            professionalId: caio,
            date: SpDate.parse(dia),
          ),
          throwsA(
            isA<ApiProblem>()
                .having((p) => p.code, 'code', ErrorCode.dateOutOfRange)
                .having((p) => p.status, 'status', 422),
          ),
        );
        await expectLater(
          book('${dia}T10:00:00'),
          throwsA(
            isA<ApiProblem>()
                .having((p) => p.code, 'code', ErrorCode.dateOutOfRange)
                .having((p) => p.status, 'status', 422),
          ),
        );
      });
    }

    test('hoje e hoje + 13 aceitam nos dois', () async {
      for (final dia in ['2026-10-07', '2026-10-20']) {
        final av = await repo.getAvailability(
          barbershopId: shop,
          serviceId: corte,
          professionalId: caio,
          date: SpDate.parse(dia),
        );
        expect(av.slots, isNotEmpty, reason: dia);
      }
      final a = await book('2026-10-07T10:00:00');
      await book('2026-10-20T10:00:00', code: a.clientCode);
    });
  });

  group('seed e persistência do mock', () {
    test(
      'CT-00-33 / CT-16-01 seed: Navalha, 2 profissionais e os 3 serviços',
      () async {
        repo = MockClienteRepository(clock: clock);
        final list = await repo.listBarbershops();
        expect(list.single.name, 'Barbearia Navalha');
        expect(list.single.startingPriceCents, 3000);
        final d = await repo.getBarbershop(shop);
        expect(d.professionals.map((p) => p.name), ['Caio', 'Helena']);
        expect(
          d.services.map(
            (s) => '${s.name} ${s.durationMinutes} ${s.priceCents}',
          ),
          ['Corte 30 4000', 'Barba 30 3000', 'Corte + Barba 60 6000'],
        );
        final s = await repo.state;
        expect(s.clients.any((c) => c.phone == MockSeed.joaoPhone), isTrue);
      },
    );

    test('barbearia que não existe é 404', () async {
      await expectLater(
        repo.getBarbershop('nao-existe'),
        throwsA(problem(ErrorCode.notFound)),
      );
    });

    test(
      'estado salvo de versão antiga (telefone sem +) é trocado pelo seed',
      () async {
        final store = MemoryMockPersistence();
        await store.save({'version': 1, 'clients': [], 'codes': {}});
        final r = MockClienteRepository(clock: clock, persistence: store);
        final s = await r.state;
        expect(s.clients.map((c) => c.phone), contains(MockSeed.joaoPhone));
        expect((await store.load())!['version'], MockState.schemaVersion);
      },
    );

    test('CT-04-09 os dados continuam depois de fechar o app', () async {
      final store = MemoryMockPersistence();
      final r1 = MockClienteRepository(clock: clock, persistence: store);
      final created = await r1.createClientBooking(
        barbershopId: shop,
        idempotencyKey: 'p',
        request: ClientBookingRequest(
          serviceId: corte,
          professionalId: helena,
          startAt: sp('2026-10-09T16:00:00'),
          client: const ClientInfo(name: 'Ana', phone: '(31) 99876-5432'),
        ),
      );
      final r2 = MockClienteRepository(clock: clock, persistence: store);
      final list = await r2.listMyBookings(clientCode: created.clientCode!);
      expect(list.single.id, created.booking.id);
      expect(list.single.startAt, sp('2026-10-09T16:00:00'));
    });
  });
}
