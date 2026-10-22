import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/core/time/sao_paulo.dart';
import 'package:cortaaqui/data/mock/mock_casa_repository.dart';
import 'package:cortaaqui/data/mock/mock_casa_state.dart';
import 'package:cortaaqui/data/mock/mock_cliente_repository.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:cortaaqui/data/mock/mock_state.dart';
import 'package:cortaaqui/data/models/booking.dart';
import 'package:cortaaqui/data/models/staff.dart';
import 'package:cortaaqui/domain/scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime sp(String local) => DateTime.parse('$local-03:00').toUtc();

const shop = MockSeed.shopId;
const caio = MockSeed.caioId;
const helena = MockSeed.helenaId;
const pw = MockCasaSeed.mockPassword;

Matcher problem(ErrorCode code, [int? status]) => isA<ApiProblem>()
    .having((p) => p.code, 'code', code)
    .having((p) => status == null || p.status == status, 'status', true);

void main() {
  late FixedClock clock;
  late MockState shared;
  late MockCasaRepository repo;
  var k = 0;
  String key() => 'key-${k++}';

  // Hoje = quarta 07/10/2026 09:00. Amanhã (quinta 08/10) o seed tem: João
  // 10:00 com o Caio (pelo app), Rafael 11:00 Corte + Barba com o Caio (pela
  // Casa) e um bloqueio do Caio 14:00–15:00.
  final thu = const SpDate(2026, 10, 8);

  setUp(() {
    clock = FixedClock(sp('2026-10-07T09:00:00'));
    shared = MockSeed.build(clock.now());
    repo = MockCasaRepository(clock: clock, initialState: shared);
  });

  Future<String> login(String email) async =>
      (await repo.login(email: email, password: pw)).accessToken;
  Future<String> manager() => login(MockCasaSeed.marinaEmail);
  Future<String> caioT() => login(MockCasaSeed.caioEmail);
  Future<String> helenaT() => login(MockCasaSeed.helenaEmail);

  group('login e /auth/me', () {
    test('senha errada e e-mail desconhecido dão o mesmo 401', () async {
      expect(
        repo.login(email: MockCasaSeed.marinaEmail, password: 'errada-123'),
        throwsA(problem(ErrorCode.unauthorized, 401)),
      );
      expect(
        repo.login(email: 'ninguem@x.mock', password: pw),
        throwsA(problem(ErrorCode.unauthorized, 401)),
      );
    });

    test('papéis: gerente sem agenda (professionalId null), gerente que '
        'atende e profissional', () async {
      final m = await repo.me(await manager());
      final mm = m.membershipAt(shop)!;
      expect(mm.roles, {StaffRole.manager});
      expect(mm.professionalId, isNull);
      expect(mm.attends, isFalse);

      final h = (await repo.me(await helenaT())).membershipAt(shop)!;
      expect(h.roles, {StaffRole.manager, StaffRole.professional});
      expect(h.professionalId, helena);

      final c = (await repo.me(await caioT())).membershipAt(shop)!;
      expect(c.roles, {StaffRole.professional});
      expect(c.professionalId, caio);
    });

    test('token desconhecido dá 401', () {
      expect(repo.me('nada'), throwsA(problem(ErrorCode.unauthorized, 401)));
    });
  });

  group('agenda (CT-02)', () {
    test('CT-02-01 gerente vê todos os ativos e filtra um', () async {
      final t = await manager();
      final all = await repo.getAgenda(t, barbershopId: shop, date: thu);
      expect(all.professionals.map((p) => p.professional.name), [
        'Caio',
        'Helena',
      ]);
      final one = await repo.getAgenda(
        t,
        barbershopId: shop,
        date: thu,
        professionalId: helena,
      );
      expect(one.professionals.single.professional.id, helena);
    });

    test('CT-02-22 profissional: sem filtro só a dele; outro dá 403', () async {
      final t = await caioT();
      final own = await repo.getAgenda(t, barbershopId: shop, date: thu);
      expect(own.professionals.single.professional.id, caio);
      expect(
        repo.getAgenda(t, barbershopId: shop, date: thu, professionalId: helena),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
    });

    test('CT-02-24 overlapsBlock: só a marcação embaixo do bloqueio', () async {
      final t = await manager();
      await repo.createBlock(
        t,
        barbershopId: shop,
        professionalId: caio,
        startAt: thu.at(9 * 60 + 30),
        endAt: thu.at(10 * 60 + 30),
      );
      final a = await repo.getAgenda(
        t,
        barbershopId: shop,
        date: thu,
        professionalId: caio,
      );
      final byHour = {
        for (final b in a.professionals.single.bookings)
          spMinuteOfDay(b.startAt) ~/ 60: b.overlapsBlock,
      };
      expect(byHour, {10: true, 11: false});
    });

    test('profissional desativado some da agenda', () async {
      final t = await manager();
      await repo.updateProfessional(
        t,
        barbershopId: shop,
        professionalId: helena,
        active: false,
      );
      final a = await repo.getAgenda(t, barbershopId: shop, date: thu);
      expect(a.professionals.map((p) => p.professional.id), [caio]);
    });

    test('CT-07-03 folga não apaga a marcação', () async {
      final t = await manager();
      await repo.createTimeOff(
        t,
        barbershopId: shop,
        professionalId: caio,
        startAt: thu.at(0),
        endAt: thu.addDays(1).at(0),
      );
      final a = await repo.getAgenda(
        t,
        barbershopId: shop,
        date: thu,
        professionalId: caio,
      );
      expect(a.professionals.single.workingWindows, isEmpty);
      expect(a.professionals.single.bookings, hasLength(2));
    });
  });

  group('marcação e balcão (CT-06)', () {
    StaffBookingRequest counter(DateTime at, {String? phone, String? pro}) =>
        StaffBookingRequest(
          serviceId: MockSeed.corteId,
          professionalId: pro ?? caio,
          startAt: at,
          source: BookingSource.counter,
          newClientName: 'Balcão Silva',
          newClientPhone: phone,
        );

    test('CT-06-01 balcão sem telefone: ficha com phone null', () async {
      final t = await caioT();
      final b = await repo.createStaffBooking(
        t,
        barbershopId: shop,
        idempotencyKey: key(),
        request: counter(thu.at(9 * 60)),
      );
      expect(b.client.phone, isNull);
      final file = await repo.getClient(
        t,
        barbershopId: shop,
        clientId: b.client.id,
      );
      expect(file.client.phone, isNull);
      expect(file.client.hasDevice, isFalse);
    });

    test('STAFF sem telefone dá 422', () {
      return manager().then((t) {
        expect(
          repo.createStaffBooking(
            t,
            barbershopId: shop,
            idempotencyKey: key(),
            request: StaffBookingRequest(
              serviceId: MockSeed.corteId,
              professionalId: caio,
              startAt: thu.at(9 * 60),
              source: BookingSource.staff,
              newClientName: 'Sem Fone',
            ),
          ),
          throwsA(problem(ErrorCode.validationError, 422)),
        );
      });
    });

    test('CT-06-03 sobreposição dá SLOT_TAKEN', () async {
      final t = await manager();
      expect(
        repo.createStaffBooking(
          t,
          barbershopId: shop,
          idempotencyKey: key(),
          request: counter(thu.at(9 * 60 + 30)).copyCombo(),
        ),
        throwsA(problem(ErrorCode.slotTaken, 409)),
      );
    });

    test('CT-06-12 slot em andamento sim, terminado não', () async {
      final t = await manager();
      final today = SpDate.of(clock.now());
      clock.set(sp('2026-10-07T10:29:59'));
      await repo.createStaffBooking(
        t,
        barbershopId: shop,
        idempotencyKey: key(),
        request: counter(today.at(10 * 60)),
      );
      clock.set(sp('2026-10-07T10:30:00'));
      expect(
        repo.createStaffBooking(
          t,
          barbershopId: shop,
          idempotencyKey: key(),
          request: counter(today.at(10 * 60), pro: caio).withName('Outro Nome'),
        ),
        throwsA(problem(ErrorCode.slotInPast, 422)),
      );
    });

    test('CT-06-08 hoje + 14 dá DATE_OUT_OF_RANGE', () async {
      final t = await manager();
      expect(
        repo.createStaffBooking(
          t,
          barbershopId: shop,
          idempotencyKey: key(),
          request: counter(const SpDate(2026, 10, 21).at(9 * 60)),
        ),
        throwsA(problem(ErrorCode.dateOutOfRange, 422)),
      );
    });

    test('profissional não marca na agenda de outro (403)', () async {
      final t = await caioT();
      expect(
        repo.createStaffBooking(
          t,
          barbershopId: shop,
          idempotencyKey: key(),
          request: counter(thu.at(16 * 60), pro: helena),
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
    });

    test('gerente sem agenda própria marca em qualquer agenda', () async {
      final t = await manager();
      final b = await repo.createStaffBooking(
        t,
        barbershopId: shop,
        idempotencyKey: key(),
        request: counter(thu.at(16 * 60), pro: helena),
      );
      expect(b.professional.id, helena);
    });
  });

  group('status (CT-02, CT-00-45)', () {
    const joaoBooking = '6f1c2a10-0000-4000-8000-0000000000d1';

    test('CT-02-12 concluir antes do início dá TOO_EARLY', () async {
      final t = await caioT();
      clock.set(sp('2026-10-08T09:59:59'));
      expect(
        repo.changeBookingStatus(
          t,
          barbershopId: shop,
          bookingId: joaoBooking,
          idempotencyKey: key(),
          status: BookingStatus.completed,
        ),
        throwsA(problem(ErrorCode.tooEarly, 422)),
      );
    });

    test('CT-02-23 chave nova depois de mudar dá STATUS_CHANGED; mesma chave '
        'devolve o mesmo', () async {
      final g = await manager();
      final c = await caioT();
      clock.set(sp('2026-10-08T10:10:00'));
      const k1 = 'same-key';
      final done = await repo.changeBookingStatus(
        g,
        barbershopId: shop,
        bookingId: joaoBooking,
        idempotencyKey: k1,
        status: BookingStatus.completed,
      );
      expect(done.professionalPercent, 60);
      expect(done.shopPercent, 40);
      final again = await repo.changeBookingStatus(
        g,
        barbershopId: shop,
        bookingId: joaoBooking,
        idempotencyKey: k1,
        status: BookingStatus.completed,
      );
      expect(again.status, BookingStatus.completed);
      expect(
        repo.changeBookingStatus(
          c,
          barbershopId: shop,
          bookingId: joaoBooking,
          idempotencyKey: key(),
          status: BookingStatus.noShow,
        ),
        throwsA(problem(ErrorCode.statusChanged, 409)),
      );
    });

    test('CT-02-11 Casa cancela a qualquer hora e grava canceledBy STAFF', () async {
      final t = await caioT();
      clock.set(sp('2026-10-08T10:10:00'));
      final b = await repo.changeBookingStatus(
        t,
        barbershopId: shop,
        bookingId: joaoBooking,
        idempotencyKey: key(),
        status: BookingStatus.canceled,
      );
      expect(b.canceledBy, CanceledBy.staff);
    });

    test('CONCURRENT_UPDATE do servidor chega como ApiProblem e nada muda', () async {
      final r = MockCasaRepository(
        clock: clock,
        initialState: shared,
        faultInjector: (op) => op == 'changeBookingStatus'
            ? const ApiProblem(ErrorCode.concurrentUpdate, status: 409)
            : null,
      );
      final t = (await r.login(email: MockCasaSeed.marinaEmail, password: pw))
          .accessToken;
      expect(
        r.changeBookingStatus(
          t,
          barbershopId: shop,
          bookingId: joaoBooking,
          idempotencyKey: key(),
          status: BookingStatus.canceled,
        ),
        throwsA(problem(ErrorCode.concurrentUpdate, 409)),
      );
      expect(
        shared.bookings.firstWhere((b) => b.id == joaoBooking).status,
        BookingStatus.scheduled,
      );
    });
  });

  group('bloqueio (CT-02)', () {
    test('CT-02-16/18 fora da grade e fim antes do início: 422', () async {
      final t = await caioT();
      for (final (s, e) in [(615, 660), (600, 645), (660, 660), (660, 630)]) {
        expect(
          repo.createBlock(
            t,
            barbershopId: shop,
            professionalId: caio,
            startAt: thu.at(s),
            endAt: thu.at(e),
          ),
          throwsA(problem(ErrorCode.validationError, 422)),
          reason: '$s-$e',
        );
      }
    });

    test('CT-02-21 termina 00:00 sim; passa da meia-noite não', () async {
      final t = await caioT();
      await repo.createBlock(
        t,
        barbershopId: shop,
        professionalId: caio,
        startAt: thu.at(23 * 60 + 30),
        endAt: thu.addDays(1).at(0),
      );
      expect(
        repo.createBlock(
          t,
          barbershopId: shop,
          professionalId: caio,
          startAt: thu.at(23 * 60),
          endAt: thu.addDays(1).at(30),
        ),
        throwsA(problem(ErrorCode.validationError, 422)),
      );
    });

    test('CT-02-26 bloqueio sobre bloqueio 409; encostado aceito', () async {
      final t = await caioT();
      expect(
        repo.createBlock(
          t,
          barbershopId: shop,
          professionalId: caio,
          startAt: thu.at(14 * 60 + 30),
          endAt: thu.at(15 * 60 + 30),
        ),
        throwsA(problem(ErrorCode.slotTaken, 409)),
      );
      await repo.createBlock(
        t,
        barbershopId: shop,
        professionalId: caio,
        startAt: thu.at(15 * 60),
        endAt: thu.at(16 * 60),
      );
    });

    test('CT-02-20 profissional não desbloqueia bloqueio de outro', () async {
      final g = await manager();
      final b = await repo.createBlock(
        g,
        barbershopId: shop,
        professionalId: helena,
        startAt: thu.at(16 * 60),
        endAt: thu.at(17 * 60),
      );
      expect(
        repo.deleteBlock(await caioT(), barbershopId: shop, blockId: b.id),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
    });
  });

  group('equipe (CT-10) e desativação', () {
    test('/professionals só do gerente e traz inativos com active', () async {
      expect(
        repo.listProfessionals(await caioT(), barbershopId: shop),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
      final g = await manager();
      await repo.updateProfessional(
        g,
        barbershopId: shop,
        professionalId: helena,
        active: false,
      );
      final list = await repo.listProfessionals(g, barbershopId: shop);
      expect({for (final p in list) p.name: p.active}, {
        'Caio': true,
        'Helena': false,
      });
    });

    test('desativar com horário futuro: PROFESSIONAL_HAS_FUTURE_BOOKINGS', () async {
      expect(
        repo.updateProfessional(
          await manager(),
          barbershopId: shop,
          professionalId: caio,
          active: false,
        ),
        throwsA(problem(ErrorCode.professionalHasFutureBookings, 409)),
      );
    });

    test('gerente desativado como profissional continua gerente, com '
        'professionalId null', () async {
      final g = await manager();
      final h = await helenaT();
      await repo.updateProfessional(
        g,
        barbershopId: shop,
        professionalId: helena,
        active: false,
      );
      final m = (await repo.me(h)).membershipAt(shop)!;
      expect(m.roles, {StaffRole.manager});
      expect(m.professionalId, isNull);
      // Sem "minha agenda": a agenda dela é a da casa inteira (gerente).
      final a = await repo.getAgenda(h, barbershopId: shop, date: thu);
      expect(a.professionals.map((p) => p.professional.id), [caio]);
      // Reativar devolve o vínculo.
      await repo.updateProfessional(
        g,
        barbershopId: shop,
        professionalId: helena,
        active: true,
      );
      expect((await repo.me(h)).membershipAt(shop)!.professionalId, helena);
    });

    test('profissional desativado sem outro vínculo: 401 no token e no login', () async {
      final g = await manager();
      final c = await caioT();
      // Tira os futuros do Caio antes (o gerente cancela).
      for (final id in [
        '6f1c2a10-0000-4000-8000-0000000000d1',
        '6f1c2a10-0000-4000-8000-0000000000d4',
      ]) {
        await repo.changeBookingStatus(
          g,
          barbershopId: shop,
          bookingId: id,
          idempotencyKey: key(),
          status: BookingStatus.canceled,
        );
      }
      await repo.updateProfessional(
        g,
        barbershopId: shop,
        professionalId: caio,
        active: false,
      );
      expect(repo.me(c), throwsA(problem(ErrorCode.unauthorized, 401)));
      expect(
        repo.login(email: MockCasaSeed.caioEmail, password: pw),
        throwsA(problem(ErrorCode.unauthorized, 401)),
      );
    });

    test('profissional desativado aqui com vínculo ativo em outra: 403 aqui', () async {
      final casa = MockCasaSeed.build();
      casa.staff
          .firstWhere((s) => s.id == MockCasaSeed.helenaUserId)
          .memberships
        ..clear()
        ..addAll([
          MockMembership(
            barbershopId: shop,
            roles: {StaffRole.professional},
            professionalId: helena,
          ),
          MockMembership(
            barbershopId: 'outra-barbearia',
            roles: {StaffRole.manager},
          ),
        ]);
      final r = MockCasaRepository(
        clock: clock,
        initialState: shared,
        initialCasa: casa,
      );
      final g = (await r.login(email: MockCasaSeed.marinaEmail, password: pw))
          .accessToken;
      final h = (await r.login(email: MockCasaSeed.helenaEmail, password: pw))
          .accessToken;
      await r.updateProfessional(
        g,
        barbershopId: shop,
        professionalId: helena,
        active: false,
      );
      expect(
        r.getAgenda(h, barbershopId: shop, date: thu),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
      expect((await r.me(h)).memberships.single.barbershopId, 'outra-barbearia');
    });

    test('CT-10-07 duração: 30 a 480 em múltiplos de 30', () async {
      final g = await manager();
      for (final bad in [0, -30, 45, 510]) {
        expect(
          repo.updateService(
            g,
            barbershopId: shop,
            serviceId: MockSeed.corteId,
            patch: ServicePatch(durationMinutes: bad),
          ),
          throwsA(problem(ErrorCode.validationError, 422)),
          reason: '$bad',
        );
      }
      final ok = await repo.updateService(
        g,
        barbershopId: shop,
        serviceId: MockSeed.corteId,
        patch: const ServicePatch(durationMinutes: 480),
      );
      expect(ok.durationMinutes, 480);
    });
  });

  group('expediente (CT-07)', () {
    test('CT-07-08/09 só 08:00–21:00 na grade de 30 min', () async {
      final g = await manager();
      for (final w in [
        WorkWindow.hm('07:30', '18:00'),
        WorkWindow.hm('09:00', '21:30'),
        WorkWindow.hm('08:15', '18:00'),
        WorkWindow.hm('08:00', '17:45'),
      ]) {
        expect(
          repo.replaceWorkingHours(
            g,
            barbershopId: shop,
            professionalId: caio,
            days: {2: [w]},
          ),
          throwsA(problem(ErrorCode.validationError, 422)),
        );
      }
      final ok = await repo.replaceWorkingHours(
        g,
        barbershopId: shop,
        professionalId: caio,
        days: {
          2: [WorkWindow.hm('08:00', '21:00')],
        },
      );
      expect(ok[2], [WorkWindow.hm('08:00', '21:00')]);
    });

    test('CT-07-07 profissional não muda expediente nem folga (403)', () async {
      final c = await caioT();
      expect(
        repo.replaceWorkingHours(
          c,
          barbershopId: shop,
          professionalId: caio,
          days: const {},
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
      expect(
        repo.createTimeOff(
          c,
          barbershopId: shop,
          professionalId: caio,
          startAt: thu.at(0),
          endAt: thu.addDays(1).at(0),
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
    });
  });

  group('clientes (CT-17)', () {
    test('CT-17-04 busca por nome sem acento e por telefone com máscara', () async {
      final t = await caioT();
      for (final q in ['joão', 'JOAO', 'alm', '(11) 98765-4321', '98765']) {
        final r = await repo.searchClients(t, barbershopId: shop, q: q);
        expect(r.map((c) => c.id), contains(MockSeed.joaoId), reason: q);
      }
    });

    test('CT-17-07 profissional cadastra; telefone repetido PHONE_IN_USE', () async {
      final t = await caioT();
      final c = await repo.createClient(
        t,
        barbershopId: shop,
        name: 'Ana Lima',
        phone: '(11) 91234-0000',
      );
      expect(c.phone, '+5511912340000');
      expect(
        repo.createClient(
          t,
          barbershopId: shop,
          name: 'Outro',
          phone: '+55 11 98765-4321',
        ),
        throwsA(problem(ErrorCode.phoneInUse, 409)),
      );
    });

    test('só o gerente edita a ficha; profissional leva 403 em qualquer uma', () async {
      final c = await caioT();
      final h = await helenaT();
      expect(
        repo.updateClient(
          c,
          barbershopId: shop,
          clientId: MockSeed.joaoId,
          name: 'João A.',
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
      final ok = await repo.updateClient(
        h,
        barbershopId: shop,
        clientId: MockSeed.joaoId,
        name: 'João A.',
      );
      expect(ok.name, 'João A.');
    });
  });

  group('liberar aparelho (CT-17-19 a 28)', () {
    test('só o gerente (403 pro profissional)', () async {
      expect(
        repo.releaseDevice(
          await caioT(),
          barbershopId: shop,
          clientId: MockSeed.joaoId,
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
    });

    test('sem agendamento pelo app aqui: DEVICE_RELEASE_NOT_ALLOWED', () async {
      // Rafael só tem horário marcado pela Casa.
      expect(
        repo.releaseDevice(
          await manager(),
          barbershopId: shop,
          clientId: MockSeed.rafaelId,
        ),
        throwsA(problem(ErrorCode.deviceReleaseNotAllowed, 409)),
      );
    });

    test('liberado: o aparelho do cliente passa a dar 401', () async {
      final cliente = MockClienteRepository(clock: clock, initialState: shared);
      expect(
        await cliente.listMyBookings(clientCode: MockSeed.joaoDeviceCode),
        isNotEmpty,
      );
      final g = await manager();
      expect(
        (await repo.getClient(
          g,
          barbershopId: shop,
          clientId: MockSeed.joaoId,
        )).client.hasDevice,
        isTrue,
      );
      await repo.releaseDevice(g, barbershopId: shop, clientId: MockSeed.joaoId);
      expect(
        cliente.listMyBookings(clientCode: MockSeed.joaoDeviceCode),
        throwsA(problem(ErrorCode.unauthorized, 401)),
      );
      expect(
        (await repo.getClient(
          g,
          barbershopId: shop,
          clientId: MockSeed.joaoId,
        )).client.hasDevice,
        isFalse,
      );
    });
  });

  group('caixa (CT-08) e % (CT-20)', () {
    Future<void> completeAll(String t) async {
      clock.set(sp('2026-10-08T13:00:00'));
      for (final id in [
        '6f1c2a10-0000-4000-8000-0000000000d1',
        '6f1c2a10-0000-4000-8000-0000000000d4',
      ]) {
        await repo.changeBookingStatus(
          t,
          barbershopId: shop,
          bookingId: id,
          idempotencyKey: key(),
          status: BookingStatus.completed,
        );
      }
    }

    test('CT-08-15 gerente: total, linhas e shopCents; casa + pros = bruto', () async {
      final g = await manager();
      await completeAll(g);
      final cash = await repo.getCash(g, barbershopId: shop, month: '2026-10');
      expect(cash.totals.grossCents, 10000);
      expect(cash.totals.shopCents, 4000);
      expect(cash.byProfessional, hasLength(2));
      expect(
        cash.totals.shopCents! +
            cash.byProfessional.fold<int>(
              0,
              (s, r) => s + r.totals.professionalCents,
            ),
        cash.totals.grossCents,
      );
    });

    test('CT-08-13 profissional: só a linha dele e sem shopCents', () async {
      await completeAll(await manager());
      final c = await caioT();
      final cash = await repo.getCash(c, barbershopId: shop, month: '2026-10');
      expect(cash.byProfessional.single.professional.id, caio);
      expect(cash.totals.toJson().containsKey('shopCents'), isFalse);
      expect(
        cash.byProfessional.single.totals.toJson().containsKey('shopCents'),
        isFalse,
      );
      expect(cash.totals.professionalCents, 6000);
    });

    test('CT-08-10 profissional pedindo outro: 403; o dele sem shopPercent', () async {
      await completeAll(await manager());
      final c = await caioT();
      expect(
        repo.getProfessionalCash(
          c,
          barbershopId: shop,
          professionalId: helena,
          month: '2026-10',
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
      final own = await repo.getProfessionalCash(
        c,
        barbershopId: shop,
        professionalId: caio,
        month: '2026-10',
      );
      expect(own.totals.shopCents, isNull);
      expect(own.bookings.every((b) => b.shopPercent == null), isTrue);
    });

    test('CT-20-10 /commission só do gerente', () async {
      final c = await caioT();
      expect(
        repo.getCommission(c, barbershopId: shop),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
      expect(
        repo.replaceCommission(
          c,
          barbershopId: shop,
          settings: const CommissionSettings(
            standard: CommissionSplit.standard,
            professionals: {},
          ),
        ),
        throwsA(problem(ErrorCode.forbidden, 403)),
      );
    });

    test('CT-20-03 % que não soma 100 ou fora de 0..100 é recusada', () async {
      final g = await manager();
      for (final (s, p) in [(40, 70), (-1, 101), (101, -1)]) {
        expect(
          repo.replaceCommission(
            g,
            barbershopId: shop,
            settings: CommissionSettings(
              standard: CommissionSplit.standard,
              professionals: {
                caio: CommissionSplit(shopPercent: s, professionalPercent: p),
              },
            ),
          ),
          throwsA(isA<ApiProblem>()),
        );
      }
    });

    test('CT-20-08 arredondamento HALF_UP por agendamento', () {
      expect(professionalShare(5, 50), 3);
      expect(professionalShare(1, 50), 1);
      expect(professionalShare(3333, 60), 2000);
      expect(professionalShare(3333, 50), 1667);
      expect(professionalShare(1001, 33), 330);
      expect(professionalShare(4000, 0), 0);
      expect(professionalShare(4000, 100), 4000);
    });

    test('mês fora de AAAA-MM dá 422', () async {
      expect(
        repo.getCash(await manager(), barbershopId: shop, month: '2026-13'),
        throwsA(problem(ErrorCode.validationError, 422)),
      );
    });
  });
}

extension on StaffBookingRequest {
  StaffBookingRequest copyCombo() => StaffBookingRequest(
    serviceId: MockSeed.comboId,
    professionalId: professionalId,
    startAt: startAt,
    source: source,
    newClientName: newClientName,
    newClientPhone: newClientPhone,
  );

  StaffBookingRequest withName(String name) => StaffBookingRequest(
    serviceId: serviceId,
    professionalId: professionalId,
    startAt: startAt,
    source: source,
    newClientName: name,
    newClientPhone: newClientPhone,
  );
}
