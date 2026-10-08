import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/phone/phone.dart';
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

  /// Código do aparelho de cada telefone nos testes: um aparelho por número
  /// (o código nasce no aparelho e fica preso ao telefone no 1º aceito).
  String k(String phone) {
    final digits = (normalizePhone(phone) ?? phone).replaceAll(
      RegExp(r'\D'),
      '',
    );
    final tail = digits.padLeft(12, '0');
    return '00000000-0000-4000-8000-${tail.substring(tail.length - 12)}';
  }

  final kT1 = k('11987654321');

  /// Códigos de outros aparelhos nos testes (UUID, como no contrato).
  String kc(int n) => '00000000-0000-4000-8000-${'$n'.padLeft(12, 'a')}';

  /// Agenda pelo app. Por padrão manda nome e telefone com o código do aparelho
  /// daquele telefone (ou o [code] dado).
  Future<Booking> book(
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
    clientCode: code ?? k(phone),
    request: ClientBookingRequest(
      serviceId: service,
      professionalId: pro,
      startAt: sp(start),
      client: ClientInfo(name: name, phone: phone),
    ),
  );

  Future<Booking> cancel(String code, String bookingId, {String? idem}) =>
      repo.cancelMyBooking(
        clientCode: code,
        bookingId: bookingId,
        idempotencyKey: idem ?? nextKey(),
      );

  group('agendar (história 1)', () {
    test(
      'CT-01-01 cria agendado com preço gravado; a resposta não traz código e '
      'o código do aparelho fica preso ao telefone',
      () async {
        final r = await book('2026-10-07T10:00:00');
        final s = await repo.state;
        expect(s.codes, {kT1: r.client.id});
        expect(r.status, BookingStatus.scheduled);
        expect(r.source, BookingSource.clientApp);
        expect(r.barbershopId, shop);
        expect(r.professional.id, caio);
        expect(r.priceCents, 4000);
        expect(r.endAt, sp('2026-10-07T10:30:00'));
        expect(r.client.phone, isNull, reason: 'cliente não vê telefone');
      },
    );

    test('aparelho preso: o 2º agendamento com o mesmo código vai para o mesmo '
        'cliente, com ou sem nome e telefone', () async {
      final first = await book('2026-10-07T10:00:00');
      final second = await book('2026-10-08T10:00:00');
      expect(second.client.id, first.client.id);
      expect((await repo.state).codes, hasLength(1));
    });

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

    test('X-Client-Code fora do formato UUID: 401', () async {
      await expectLater(
        book('2026-10-07T10:00:00', code: 'nao-e-uuid'),
        throwsA(problem(ErrorCode.unauthorized)),
      );
      expect((await repo.state).codes, isEmpty);
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
      await cancel(kT1, a.id);
      await book('2026-10-10T10:00:00');
    });

    test('CT-01-21 passado e status final não contam', () async {
      final s = await repo.state;
      final first = await book('2026-10-07T10:00:00');
      // Vira passado e ganha um status final.
      final i = s.bookings.indexWhere((b) => b.id == first.id);
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
      expect(s.bookings.every((b) => b.client.id == second.client.id), isTrue);
    });

    test('o que a Casa marca não conta no limite', () async {
      final seed = MockSeed.build(clock.now());
      repo = MockClienteRepository(clock: clock, initialState: seed);
      // João tem 1 futuro pelo app no seed; o do Rafael é da Casa.
      await book('2026-10-12T10:00:00', phone: '21912345678');
      await book('2026-10-13T10:00:00', phone: '21912345678');
      final joao = MockSeed.joaoDeviceCode;
      await book('2026-10-14T10:00:00', phone: '11987654321', code: joao);
      await expectLater(
        book('2026-10-15T10:00:00', phone: '11987654321', code: joao),
        throwsA(problem(ErrorCode.bookingLimitReached)),
      );
    });
  });

  group('pedido repetido (Idempotency-Key)', () {
    test(
      'CT-00-04 mesma chave 2 vezes: 1 agendamento, mesmo id, sem código',
      () async {
        final a = await book('2026-10-07T10:00:00', idem: 'mesma');
        final b = await book('2026-10-07T10:00:00', idem: 'mesma');
        expect(b.id, a.id);
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
      expect(r[0].id, r[1].id);
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
        const code = MockSeed.joaoDeviceCode;
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
        final b = await book('2026-10-07T12:00:00', pro: helena);
        clock.set(sp('2026-10-07T10:00:00'));
        final ok = await cancel(kT1, a.id);
        expect(ok.status, BookingStatus.canceled);
        expect(ok.canceledBy, CanceledBy.client);
        clock.set(sp('2026-10-07T10:00:01'));
        await expectLater(
          cancel(kT1, b.id),
          throwsA(problem(ErrorCode.cancelWindowClosed)),
        );
        final s = await repo.state;
        expect(
          s.bookings.firstWhere((x) => x.id == b.id).status,
          BookingStatus.scheduled,
        );
      },
    );

    test('canCancel vem calculado na lista', () async {
      await book('2026-10-07T12:00:00');
      var list = await repo.listMyBookings(clientCode: kT1);
      expect(list.single.canCancel, isTrue);
      clock.set(sp('2026-10-07T10:01:00'));
      list = await repo.listMyBookings(clientCode: kT1);
      expect(list.single.canCancel, isFalse);
    });

    test(
      'CT-04-05 cancelado volta para os livres e outro cliente marca',
      () async {
        final a = await book('2026-10-07T12:00:00');
        await cancel(kT1, a.id);
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

    test('CT-04-06 código inexistente ou alterado: 401', () async {
      await book('2026-10-08T10:00:00');
      for (final code in ['nao-existe', '${kT1}x']) {
        await expectLater(
          repo.listMyBookings(clientCode: code),
          throwsA(problem(ErrorCode.unauthorized)),
        );
        await expectLater(
          cancel(code, 'x'),
          throwsA(problem(ErrorCode.unauthorized)),
        );
      }
    });

    test('CT-04-07 não cancela horário de outro cliente', () async {
      final a = await book('2026-10-08T10:00:00');
      await book('2026-10-08T11:00:00', phone: '21912345678');
      await expectLater(
        cancel(k('21912345678'), a.id),
        throwsA(problem(ErrorCode.notFound)),
      );
    });

    test(
      'CT-04-10 cancelado pela barbearia: outra chave recebe STATUS_CHANGED',
      () async {
        final a = await book('2026-10-08T10:00:00');
        final s = await repo.state;
        final i = s.bookings.indexWhere((x) => x.id == a.id);
        s.bookings[i] = s.bookings[i].copyWith(
          status: BookingStatus.canceled,
          canceledBy: CanceledBy.staff,
        );
        await expectLater(
          cancel(kT1, a.id),
          throwsA(
            isA<ApiProblem>()
                .having((p) => p.code, 'code', ErrorCode.statusChanged)
                .having((p) => p.status, 'status', 409),
          ),
        );
        expect(s.bookings[i].canceledBy, CanceledBy.staff);
      },
    );

    test('CT-00-06 mesma Idempotency-Key 2 vezes: mesmo resultado, sem '
        'STATUS_CHANGED', () async {
      final a = await book('2026-10-08T10:00:00');
      final c1 = await cancel(kT1, a.id, idem: 'cancelar-1');
      final c2 = await cancel(kT1, a.id, idem: 'cancelar-1');
      expect(c2, c1);
      expect(c2.status, BookingStatus.canceled);
    });

    test(
      'CT-00-44 já cancelado pelo cliente, chave nova: STATUS_CHANGED',
      () async {
        final a = await book('2026-10-08T10:00:00');
        await cancel(kT1, a.id, idem: 'primeira');
        await expectLater(
          cancel(kT1, a.id, idem: 'segunda'),
          throwsA(problem(ErrorCode.statusChanged)),
        );
      },
    );

    test('CT-00-44 concluído e falta, chave nova: STATUS_CHANGED', () async {
      final a = await book('2026-10-08T10:00:00');
      final s = await repo.state;
      final i = s.bookings.indexWhere((x) => x.id == a.id);
      for (final st in [BookingStatus.completed, BookingStatus.noShow]) {
        s.bookings[i] = s.bookings[i].copyWith(status: st);
        await expectLater(
          cancel(kT1, a.id),
          throwsA(problem(ErrorCode.statusChanged)),
          reason: st.name,
        );
        expect(s.bookings[i].status, st);
      }
    });

    test('mesma chave de cancelamento para outro horário é recusada', () async {
      final a = await book('2026-10-08T10:00:00');
      final b = await book('2026-10-09T10:00:00');
      await cancel(kT1, a.id, idem: 'c');
      await expectLater(
        cancel(kT1, b.id, idem: 'c'),
        throwsA(problem(ErrorCode.idempotencyKeyReused)),
      );
    });
  });

  group('aparelho preso a um telefone (CT-04-08, CT-04-14 a CT-04-19)', () {
    late MockState seed;
    const joaoNext = '6f1c2a10-0000-4000-8000-0000000000d1';
    setUp(() {
      seed = MockSeed.build(clock.now());
      repo = MockClienteRepository(clock: clock, initialState: seed);
    });

    Future<void> release(String clientId) =>
        repo.releaseClientDevice(barbershopId: shop, clientId: clientId);

    Matcher onOtherDevice() => throwsA(
      isA<ApiProblem>()
          .having((p) => p.code, 'code', ErrorCode.phoneOnOtherDevice)
          .having((p) => p.status, 'status', 409)
          .having(
            clientMessageFor,
            'mensagem',
            'Esse telefone já está em outro aparelho. Fale com a barbearia.',
          ),
    );

    test('CT-04-15 telefone preso a outro aparelho: recusado nas 3 formas e '
        'sem futuro, nada gravado, K2 não fica preso', () async {
      final before = seed.bookings.length;
      for (final phone in [
        '+5511987654321',
        '(11) 98765-4321',
        '55 11 98765-4321',
      ]) {
        await expectLater(
          book('2026-10-12T10:00:00', phone: phone, code: kc(2)),
          onOtherDevice(),
          reason: phone,
        );
      }
      // João sem nenhum horário futuro: continua recusado.
      final i = seed.bookings.indexWhere((b) => b.id == joaoNext);
      seed.bookings[i] = seed.bookings[i].copyWith(
        status: BookingStatus.canceled,
        canceledBy: CanceledBy.client,
      );
      await expectLater(
        book('2026-10-12T10:00:00', code: kc(2)),
        onOtherDevice(),
      );
      expect(seed.bookings, hasLength(before));
      expect(seed.codes.keys, [MockSeed.joaoDeviceCode]);
      await expectLater(
        repo.listMyBookings(clientCode: kc(2)),
        throwsA(problem(ErrorCode.unauthorized)),
      );
    });

    test('CT-04-08 listar ou cancelar só com o telefone é recusado', () async {
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
          cancel(phone, joaoNext),
          throwsA(problem(ErrorCode.unauthorized)),
        );
      }
      expect(
        seed.bookings.firstWhere((b) => b.id == joaoNext).status,
        BookingStatus.scheduled,
      );
    });

    test('CT-04-14 / CT-04-17 nenhuma resposta traz o código', () async {
      final r = await book('2026-10-12T10:00:00', phone: '31998765432');
      expect(r.toJson().toString(), isNot(contains(k('31998765432'))));
      final list = await repo.listMyBookings(clientCode: k('31998765432'));
      expect(
        list.map((b) => b.toJson()).toString(),
        isNot(contains(k('31998765432'))),
      );
    });

    test('CT-04-19 telefone cadastrado só pela Casa: o 1º aparelho fica preso '
        'e vê os horários; o 2º cai no CT-04-15', () async {
      final r = await book(
        '2026-10-12T10:00:00',
        phone: '(21) 91234-5678',
        code: kc(3),
      );
      expect(r.client.id, MockSeed.rafaelId);
      expect(seed.codes[kc(3)], MockSeed.rafaelId);
      final list = await repo.listMyBookings(clientCode: kc(3));
      expect(list, hasLength(2), reason: 'o da Casa e o novo');
      await expectLater(
        book('2026-10-13T10:00:00', phone: '21912345678', code: kc(4)),
        onOtherDevice(),
      );
    });

    test('CT-04-20 / CT-04-21 aparelho preso a T1 mandando T2: '
        'DEVICE_PHONE_MISMATCH, nada gravado', () async {
      await book('2026-10-12T10:00:00', phone: '31998765432', code: kc(5));
      final before = seed.bookings.length;
      await expectLater(
        book('2026-10-13T10:00:00', phone: '41998765432', code: kc(5)),
        throwsA(
          isA<ApiProblem>()
              .having((p) => p.code, 'code', ErrorCode.devicePhoneMismatch)
              .having((p) => p.status, 'status', 409),
        ),
      );
      expect(seed.bookings, hasLength(before));
      expect(seed.clients.where((c) => c.phone == '+5541998765432'), isEmpty);
      // O mesmo número escrito de outro jeito passa.
      await book(
        '2026-10-13T10:00:00',
        phone: '+55 31 99876-5432',
        code: kc(5),
      );
    });

    group('CT-04-22 1º agendamento recusado não prende o aparelho', () {
      Future<void> refused(
        Future<Booking> Function() attempt,
        ErrorCode code,
      ) async {
        final codesBefore = Map.of(seed.codes);
        final clientsBefore = seed.clients.length;
        final bookingsBefore = seed.bookings.length;
        await expectLater(attempt(), throwsA(problem(code)));
        expect(seed.codes, codesBefore, reason: 'nada preso');
        expect(seed.clients, hasLength(clientsBefore), reason: 'nada criado');
        expect(seed.bookings, hasLength(bookingsBefore));
      }

      test('menos de 30 min', () async {
        await refused(
          () => book('2026-10-07T09:00:00', phone: '31998765432', code: kc(9)),
          ErrorCode.tooSoon,
        );
      });

      test('fora dos 14 dias', () async {
        await refused(
          () => book('2026-10-21T10:00:00', phone: '31998765432', code: kc(9)),
          ErrorCode.dateOutOfRange,
        );
      });

      test('horário ocupado', () async {
        // Seed: João às 10:00 com o Caio no dia 08/10.
        await refused(
          () => book('2026-10-08T10:00:00', phone: '31998765432', code: kc(9)),
          ErrorCode.slotTaken,
        );
      });

      test('telefone em outro aparelho', () async {
        await refused(
          () => book('2026-10-12T10:00:00', code: kc(9)),
          ErrorCode.phoneOnOtherDevice,
        );
      });

      test('CT-17-25 limite de 2 (telefone liberado que já tem 2 futuros): '
          'K2 não fica preso; depois que a Casa cancela 1, K2 agenda e vê '
          'os dois', () async {
        final second = await book(
          '2026-10-12T10:00:00',
          code: MockSeed.joaoDeviceCode,
        );
        await release(MockSeed.joaoId);
        await refused(
          () => book('2026-10-13T10:00:00', code: kc(9)),
          ErrorCode.bookingLimitReached,
        );
        await expectLater(
          repo.listMyBookings(clientCode: kc(9)),
          throwsA(problem(ErrorCode.unauthorized)),
        );
        // A Casa cancela 1 dos 2.
        final i = seed.bookings.indexWhere((b) => b.id == second.id);
        seed.bookings[i] = seed.bookings[i].copyWith(
          status: BookingStatus.canceled,
          canceledBy: CanceledBy.staff,
        );
        final novo = await book('2026-10-13T10:00:00', code: kc(9));
        final up = await repo.listMyBookings(clientCode: kc(9));
        expect(up.map((b) => b.id), [joaoNext, novo.id]);
      });

      test('depois de cada recusa de D1, D2 agenda com T1 e fica preso; aí D1 '
          'cai no CT-04-15', () async {
        const t = '31998765432';
        await expectLater(
          book('2026-10-07T09:00:00', phone: t, code: kc(9)),
          throwsA(problem(ErrorCode.tooSoon)),
        );
        await expectLater(
          book('2026-10-21T10:00:00', phone: t, code: kc(9)),
          throwsA(problem(ErrorCode.dateOutOfRange)),
        );
        await expectLater(
          book('2026-10-08T10:00:00', phone: t, code: kc(9)),
          throwsA(problem(ErrorCode.slotTaken)),
        );
        await book('2026-10-12T10:00:00', phone: t, code: kc(8));
        expect(seed.codes[kc(8)], isNotNull);
        expect(seed.codes.containsKey(kc(9)), isFalse);
        await expectLater(
          book('2026-10-13T10:00:00', phone: t, code: kc(9)),
          onOtherDevice(),
        );
      });

      test('depois da recusa, o mesmo aparelho agenda e fica preso', () async {
        await expectLater(
          book('2026-10-07T09:00:00', phone: '31998765432', code: kc(9)),
          throwsA(problem(ErrorCode.tooSoon)),
        );
        await book('2026-10-12T10:00:00', phone: '31998765432', code: kc(9));
        expect(seed.codes[kc(9)], isNotNull);
      });
    });

    group('troca de celular: liberação pelo gerente', () {
      test(
        'CT-17-19 o código antigo para de valer e os horários continuam',
        () async {
          await release(MockSeed.joaoId);
          const old = MockSeed.joaoDeviceCode;
          await expectLater(
            repo.listMyBookings(clientCode: old),
            throwsA(problem(ErrorCode.unauthorized)),
          );
          await expectLater(
            cancel(old, joaoNext),
            throwsA(problem(ErrorCode.unauthorized)),
          );
          // Mesmo com o telefone livre, o código revogado não volta a prender.
          await expectLater(
            book('2026-10-12T10:00:00', code: old),
            throwsA(problem(ErrorCode.unauthorized)),
          );
          expect(seed.codes.containsKey(old), isFalse);
          expect(
            seed.bookings.firstWhere((b) => b.id == joaoNext).status,
            BookingStatus.scheduled,
          );
        },
      );

      test('CT-17-20 / CT-17-24 o próximo aparelho fica preso e vê os horários '
          'de todas as barbearias', () async {
        // Um horário do João em outra barbearia (marcado pela Casa de lá).
        final base = seed.bookings.firstWhere((b) => b.id == joaoNext);
        final other = Booking(
          id: 'outra-barbearia-1',
          barbershopId: 'outra-barbearia',
          barbershopName: 'Barbearia Dois',
          status: BookingStatus.scheduled,
          source: BookingSource.staff,
          startAt: base.startAt.add(const Duration(days: 1)),
          endAt: base.endAt.add(const Duration(days: 1)),
          service: base.service,
          professional: base.professional,
          client: base.client,
          priceCents: base.priceCents,
          createdAt: base.createdAt,
        );
        seed.bookings.add(other);
        await release(MockSeed.joaoId);
        // CT-17-24: o código antigo cai em todas as barbearias.
        await expectLater(
          cancel(MockSeed.joaoDeviceCode, other.id),
          throwsA(problem(ErrorCode.unauthorized)),
        );

        final r = await book(
          '2026-10-12T10:00:00',
          phone: '+55 11 98765-4321',
          code: kc(10),
        );
        expect(r.client.id, MockSeed.joaoId);
        expect(seed.codes[kc(10)], MockSeed.joaoId);
        final up = await repo.listMyBookings(clientCode: kc(10));
        expect(up.map((b) => b.id), containsAll([joaoNext, other.id]));
        expect(up.map((b) => b.barbershopName).toSet(), {
          'Barbearia Navalha',
          'Barbearia Dois',
        });
        final past = await repo.listMyBookings(
          clientCode: kc(10),
          scope: BookingScope.past,
        );
        expect(past, hasLength(2), reason: 'o histórico também passa');
        // E um 3º aparelho cai no CT-04-15.
        await expectLater(
          book('2026-10-13T10:00:00', code: kc(11)),
          onOtherDevice(),
        );
      });

      test('sem agendamento pelo app nesta barbearia: '
          'DEVICE_RELEASE_NOT_ALLOWED', () async {
        // Rafael só tem horário marcado pela Casa.
        await expectLater(
          release(MockSeed.rafaelId),
          throwsA(
            isA<ApiProblem>()
                .having(
                  (p) => p.code,
                  'code',
                  ErrorCode.deviceReleaseNotAllowed,
                )
                .having((p) => p.status, 'status', 409),
          ),
        );
        await expectLater(
          release('cliente-que-nao-existe'),
          throwsA(problem(ErrorCode.notFound)),
        );
      });

      test('liberar de novo, já sem aparelho, não dá erro', () async {
        await release(MockSeed.joaoId);
        await release(MockSeed.joaoId);
        expect(seed.codes, isEmpty);
      });
    });
  });

  group('X-Client-Code inválido: sempre o mesmo 401 (contrato 9015a3d)', () {
    late MockState seed;
    const joaoNext = '6f1c2a10-0000-4000-8000-0000000000d1';
    setUp(() async {
      seed = MockSeed.build(clock.now());
      repo = MockClienteRepository(clock: clock, initialState: seed);
    });

    final same401 = throwsA(
      isA<ApiProblem>()
          .having((p) => p.code, 'code', ErrorCode.unauthorized)
          .having((p) => p.status, 'status', 401)
          .having((p) => p.title, 'title', kInvalidClientCode.title)
          .having((p) => p.fields, 'fields', isEmpty),
    );

    Future<void> revokeJoao() =>
        repo.releaseClientDevice(barbershopId: shop, clientId: MockSeed.joaoId);

    test('listar e cancelar: ausente, fora do formato, desconhecido e '
        'liberado', () async {
      await revokeJoao();
      for (final code in [
        '',
        'nao-e-uuid',
        '${MockSeed.joaoDeviceCode}0',
        kc(99), // UUID que o servidor não conhece
        MockSeed.joaoDeviceCode, // liberado
      ]) {
        await expectLater(
          repo.listMyBookings(clientCode: code),
          same401,
          reason: code,
        );
        await expectLater(cancel(code, joaoNext), same401, reason: code);
      }
    });

    test('agendar: ausente, fora do formato e liberado dão 401 antes de '
        'qualquer outra regra (nunca 400, 404 ou 422)', () async {
      await revokeJoao();
      for (final code in ['', 'nao-e-uuid', MockSeed.joaoDeviceCode]) {
        // Telefone inválido, barbearia que não existe e fora dos 14 dias:
        // mesmo assim o que vem é o 401.
        await expectLater(
          repo.createClientBooking(
            barbershopId: 'nao-existe',
            idempotencyKey: nextKey(),
            clientCode: code,
            request: ClientBookingRequest(
              serviceId: corte,
              professionalId: caio,
              startAt: sp('2026-10-30T10:15:00'),
              client: const ClientInfo(name: 'J', phone: 'abc'),
            ),
          ),
          same401,
          reason: code,
        );
      }
      expect(seed.codes, isEmpty);
    });

    test('código liberado repetindo uma Idempotency-Key já usada: 401, não o '
        'resultado guardado', () async {
      await book(
        '2026-10-12T10:00:00',
        code: MockSeed.joaoDeviceCode,
        idem: 'antes-da-liberacao',
      );
      await revokeJoao();
      await expectLater(
        book(
          '2026-10-12T10:00:00',
          code: MockSeed.joaoDeviceCode,
          idem: 'antes-da-liberacao',
        ),
        same401,
      );
    });

    test('UUID novo (aparelho que ainda não agendou) pode agendar', () async {
      final r = await book('2026-10-12T10:00:00', phone: '31998765432');
      expect(seed.codes[k('31998765432')], r.client.id);
    });
  });

  test('ordem dos erros: aparelho do João mandando o telefone do Rafael, que '
      'está preso a outro aparelho, dá DEVICE_PHONE_MISMATCH (o código vem '
      'antes do telefone)', () async {
    final seed = MockSeed.build(clock.now());
    repo = MockClienteRepository(clock: clock, initialState: seed);
    // Rafael fica preso a outro aparelho.
    await book('2026-10-12T10:00:00', phone: MockSeed.rafaelPhone, code: kc(3));
    expect(seed.codes[kc(3)], MockSeed.rafaelId);
    final before = seed.bookings.length;
    await expectLater(
      book(
        '2026-10-13T10:00:00',
        phone: '(21) 91234-5678',
        code: MockSeed.joaoDeviceCode,
      ),
      throwsA(
        isA<ApiProblem>()
            .having((p) => p.code, 'code', ErrorCode.devicePhoneMismatch)
            .having((p) => p.status, 'status', 409),
      ),
    );
    expect(seed.bookings, hasLength(before));
    expect(seed.codes[MockSeed.joaoDeviceCode], MockSeed.joaoId);
    expect(seed.codes[kc(3)], MockSeed.rafaelId);
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
      expect(r.client.phone, isNull);
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
      await book('2026-10-07T10:00:00');
      await book('2026-10-20T10:00:00');
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
        expect(s.codes, {MockSeed.joaoDeviceCode: MockSeed.joaoId});
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
        clientCode: kc(12),
        request: ClientBookingRequest(
          serviceId: corte,
          professionalId: helena,
          startAt: sp('2026-10-09T16:00:00'),
          client: const ClientInfo(name: 'Ana', phone: '(31) 99876-5432'),
        ),
      );
      final r2 = MockClienteRepository(clock: clock, persistence: store);
      final list = await r2.listMyBookings(clientCode: kc(12));
      expect(list.single.id, created.id);
      expect(list.single.startAt, sp('2026-10-09T16:00:00'));
    });
  });
}
