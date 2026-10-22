import '../../core/errors/api_problem.dart';
import '../../core/ids/uuid.dart';
import '../../core/phone/phone.dart';
import '../../core/time/clock.dart';
import '../../core/time/sao_paulo.dart';
import '../../domain/casa_rules.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import '../models/staff.dart';
import '../repositories/casa_repository.dart';
import 'mock_casa_state.dart';
import 'mock_cliente_repository.dart';
import 'mock_persistence.dart';
import 'mock_seed.dart';
import 'mock_state.dart';

const _unauthorized = ApiProblem(
  ErrorCode.unauthorized,
  status: 401,
  title: 'Não autorizado',
);
const _forbidden = ApiProblem(
  ErrorCode.forbidden,
  status: 403,
  title: 'Sem permissão',
);
ApiProblem _notFound(String what) =>
    ApiProblem(ErrorCode.notFound, status: 404, title: '$what não encontrado');
ApiProblem _invalid(String field, String message) => ApiProblem(
  ErrorCode.validationError,
  status: 422,
  title: 'Dados inválidos',
  fields: [ProblemField(field, message)],
);

/// Quem está pedindo, nesta barbearia.
class _Ctx {
  const _Ctx(this.staff, this.m);
  final MockStaff staff;
  final MockMembership m;

  bool get isManager => m.isManager;

  /// Agenda própria (só quem atende). `null` nunca é "minha agenda".
  String? get ownProfessionalId =>
      m.roles.contains(StaffRole.professional) ? m.professionalId : null;
}

/// "Servidor" do app Casa sem servidor. Usa o mesmo `MockState` do app Cliente
/// (marcações, bloqueios, clientes e aparelhos) e aplica as mesmas recusas do
/// contrato, com os mesmos códigos. Papel e barbearia vêm do token.
class MockCasaRepository implements CasaRepository {
  MockCasaRepository({
    required this.clock,
    MockPersistence? persistence,
    MockState? initialState,
    MockCasaState? initialCasa,
    this.latency = Duration.zero,
    this.faultInjector,
  }) : _persistence = persistence ?? MemoryMockPersistence(),
       _state = initialState,
       _casa = initialCasa {
    if (_state != null) _fixSeedPercents(_state!);
    if (_state != null && _casa == null) _casa = MockCasaSeed.build();
  }

  final Clock clock;
  final Duration latency;
  final MockPersistence _persistence;

  /// Só para teste: devolve um erro para a operação antes de mexer em nada
  /// (ex.: `CONCURRENT_UPDATE` no servidor).
  final ApiProblem? Function(String operation)? faultInjector;

  MockState? _state;
  MockCasaState? _casa;
  Future<void>? _loading;

  Future<MockState> get state async {
    await _ensure();
    return _state!;
  }

  Future<MockCasaState> get casaState async {
    await _ensure();
    return _casa!;
  }

  static void _fixSeedPercents(MockState s) {
    final fixed = MockCasaSeed.withSeedPercents(s.bookings);
    s.bookings
      ..clear()
      ..addAll(fixed);
  }

  Future<void> _ensure() {
    if (_state != null && _casa != null) return Future.value();
    return _loading ??= () async {
      final saved = await _persistence.load();
      MockState? shared;
      MockCasaState? casa;
      if (saved != null) {
        try {
          shared = MockState.fromJson(
            MockSeed.shops(),
            saved['shared'] as Map<String, dynamic>,
          );
          casa = MockCasaState.fromJson(saved['casa'] as Map<String, dynamic>);
        } catch (_) {
          shared = null;
        }
      }
      if (shared == null || casa == null) {
        shared = MockSeed.build(clock.now());
        _fixSeedPercents(shared);
        casa = MockCasaSeed.build();
      }
      _state = shared;
      _casa = casa;
      await _commit();
    }();
  }

  Future<void> _begin(String op) async {
    await _ensure();
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final fault = faultInjector?.call(op);
    if (fault != null) throw fault;
  }

  Future<void> _commit() =>
      _persistence.save({'shared': _state!.toJson(), 'casa': _casa!.toJson()});

  MockState get _s => _state!;
  MockCasaState get _c => _casa!;

  // ------------------------------------------------------------ sessão

  MockStaff _staffByToken(String token) {
    final id = _c.tokens[token];
    final staff = id == null
        ? null
        : _c.staff.where((x) => x.id == id).firstOrNull;
    // Sem vínculo ativo em nenhuma barbearia: o token deixa de valer (401).
    if (staff == null || !staff.hasActiveLink) throw _unauthorized;
    return staff;
  }

  /// 401 sem token válido; 404 sem vínculo nesta barbearia; 403 com o vínculo
  /// desativado aqui (ainda tem vínculo ativo em outra).
  _Ctx _ctx(String token, String barbershopId) {
    final staff = _staffByToken(token);
    final m = staff.memberships
        .where((x) => x.barbershopId == barbershopId)
        .firstOrNull;
    if (m == null) throw _notFound('Barbearia');
    if (!m.active) throw _forbidden;
    return _Ctx(staff, m);
  }

  _Ctx _manager(String token, String barbershopId) {
    final ctx = _ctx(token, barbershopId);
    if (!ctx.isManager) throw _forbidden;
    return ctx;
  }

  StaffUser _userOf(MockStaff staff) => StaffUser(
    id: staff.id,
    name: staff.name,
    email: staff.email,
    memberships: [
      for (final m in staff.memberships.where((m) => m.active))
        Membership(
          barbershopId: m.barbershopId,
          barbershopName: _shopName(m.barbershopId),
          roles: {...m.roles},
          professionalId: m.roles.contains(StaffRole.professional)
              ? m.professionalId
              : null,
        ),
    ],
  );

  String _shopName(String id) =>
      _s.shops.where((x) => x.detail.id == id).firstOrNull?.detail.name ??
      'Barbearia';

  @override
  Future<StaffSession> login({
    required String email,
    required String password,
  }) async {
    await _begin('login');
    final staff = _c.staff
        .where((x) => x.email == email.trim().toLowerCase())
        .firstOrNull;
    // Senha errada, e-mail desconhecido e sem vínculo ativo: o mesmo 401.
    if (staff == null || staff.password != password || !staff.hasActiveLink) {
      throw _unauthorized;
    }
    final token = newUuid();
    _c.tokens[token] = staff.id;
    await _commit();
    return StaffSession(
      accessToken: token,
      expiresAt: clock.now().add(const Duration(hours: 12)),
      user: _userOf(staff),
    );
  }

  @override
  Future<StaffUser> me(String token) async {
    await _begin('me');
    return _userOf(_staffByToken(token));
  }

  @override
  Future<void> logout(String token) async {
    await _begin('logout');
    _staffByToken(token);
    _c.tokens.remove(token);
    await _commit();
  }

  // ------------------------------------------------------------ agenda

  List<Professional> _pros(String shopId) => _c.professionals[shopId] ?? [];

  Professional _activePro(String shopId, String id) {
    final p = _pros(shopId).where((x) => x.id == id && x.active).firstOrNull;
    if (p == null) throw _notFound('Profissional');
    return p;
  }

  List<MockBlock> _blocksOf(String shopId, String proId) => _s.blocks
      .where((b) => b.barbershopId == shopId && b.professionalId == proId)
      .toList();

  /// O que a Casa recebe: telefone do cliente (o seed do app Cliente não
  /// guarda na marcação) e `overlapsBlock` calculado na leitura.
  Booking _withOverlap(Booking b) => b.copyWith(
    client: b.client.phone != null
        ? null
        : BookingClientRef(
            id: b.client.id,
            name: b.client.name,
            phone: _s.clients
                .where((c) => c.id == b.client.id)
                .firstOrNull
                ?.phone,
          ),
    overlapsBlock:
        b.status.occupiesSlot &&
        _blocksOf(
          b.barbershopId,
          b.professional.id,
        ).any((x) => x.span.overlaps(TimeSpan(b.startAt, b.endAt))),
  );

  @override
  Future<Agenda> getAgenda(
    String token, {
    required String barbershopId,
    required SpDate date,
    String? professionalId,
  }) async {
    await _begin('agenda');
    final ctx = _ctx(token, barbershopId);
    final List<Professional> pros;
    if (ctx.isManager) {
      pros = professionalId == null
          ? _pros(barbershopId).where((p) => p.active).toList()
          : [_activePro(barbershopId, professionalId)];
    } else {
      final own = ctx.ownProfessionalId;
      if (own == null) throw _forbidden;
      if (professionalId != null && professionalId != own) throw _forbidden;
      pros = [_activePro(barbershopId, own)];
    }
    final dayStart = date.at(0);
    final dayEnd = date.addDays(1).at(0);
    final day = TimeSpan(dayStart, dayEnd);
    return Agenda(
      date: date,
      professionals: [
        for (final p in pros)
          AgendaProfessional(
            professional: p.public,
            workingWindows: _c.windowsFor(p.id, date),
            bookings:
                _s.bookings
                    .where(
                      (b) =>
                          b.barbershopId == barbershopId &&
                          b.professional.id == p.id &&
                          SpDate.of(b.startAt) == date,
                    )
                    .map(_withOverlap)
                    .toList()
                  ..sort((a, b) => a.startAt.compareTo(b.startAt)),
            blocks: [
              for (final b in _blocksOf(barbershopId, p.id))
                if (!b.startAt.isBefore(dayStart) && b.startAt.isBefore(dayEnd))
                  Block(
                    id: b.id,
                    professionalId: b.professionalId,
                    startAt: b.startAt,
                    endAt: b.endAt,
                  ),
            ],
            timeOff: _c.timeOff
                .where((t) => t.professionalId == p.id && t.span.overlaps(day))
                .toList(),
          ),
      ],
    );
  }

  Service _service(String shopId, String id) {
    final x = (_c.services[shopId] ?? [])
        .where((x) => x.id == id && x.active)
        .firstOrNull;
    if (x == null) throw _notFound('Serviço');
    return x;
  }

  @override
  Future<Booking> createStaffBooking(
    String token, {
    required String barbershopId,
    required String idempotencyKey,
    required StaffBookingRequest request,
  }) async {
    await _begin('createStaffBooking');
    final ctx = _ctx(token, barbershopId);
    final r = request;
    final fingerprint =
        'staff|$barbershopId|${r.professionalId}|${r.serviceId}|'
        '${r.startAt.toIso8601String()}|${r.source.wire}|${r.clientId}|'
        '${r.newClientName}|${r.newClientPhone}';
    final seen = _s.idempotency[idempotencyKey];
    if (seen != null) {
      if (seen.fingerprint != fingerprint) {
        throw const ApiProblem(
          ErrorCode.idempotencyKeyReused,
          status: 422,
          title: 'Chave já usada com outro pedido',
        );
      }
      return _withOverlap(
        _s.bookings.firstWhere((b) => b.id == seen.bookingId),
      );
    }
    if (!ctx.isManager && r.professionalId != ctx.ownProfessionalId) {
      throw _forbidden;
    }
    final pro = _activePro(barbershopId, r.professionalId);
    final svc = _service(barbershopId, r.serviceId);
    final now = clock.now();
    if (!isOnGrid(r.startAt)) {
      throw _invalid('startAt', 'Horário fora da grade de 30 min');
    }
    final date = SpDate.of(r.startAt);
    if (!isWithinHorizon(date, now)) {
      throw const ApiProblem(
        ErrorCode.dateOutOfRange,
        status: 422,
        title: 'Fora dos 14 dias',
      );
    }
    // Casa: vale o slot de 30 min em andamento; o que já terminou, não.
    final slotEnd = r.startAt.add(
      const Duration(minutes: SchedulingRules.slotMinutes),
    );
    if (!slotEnd.isAfter(now)) {
      throw const ApiProblem(
        ErrorCode.slotInPast,
        status: 422,
        title: 'Horário já passou',
      );
    }
    if (!fitsWorkingHours(
      r.startAt,
      svc.durationMinutes,
      _c.windowsFor(pro.id, date),
    )) {
      throw const ApiProblem(
        ErrorCode.outsideWorkingHours,
        status: 422,
        title: 'Fora do expediente',
      );
    }
    final busy = busySpans(
      bookings: _s.bookings.where(
        (b) => b.barbershopId == barbershopId && b.professional.id == pro.id,
      ),
      blocks: _blocksOf(barbershopId, pro.id).map((b) => b.span),
    );
    if (overlapsBusy(r.startAt, svc.durationMinutes, busy)) {
      throw const ApiProblem(
        ErrorCode.slotTaken,
        status: 409,
        title: 'Horário ocupado',
      );
    }
    final client = _resolveClient(barbershopId, r);
    final booking = Booking(
      id: newUuid(),
      barbershopId: barbershopId,
      barbershopName: _shopName(barbershopId),
      status: BookingStatus.scheduled,
      source: r.source,
      startAt: r.startAt,
      endAt: r.startAt.add(Duration(minutes: svc.durationMinutes)),
      service: BookingServiceRef(id: svc.id, name: svc.name),
      professional: pro.public,
      client: BookingClientRef(
        id: client.id,
        name: client.fichaNames[barbershopId] ?? client.name,
        phone: client.phone,
      ),
      priceCents: svc.priceCents,
      note: r.note,
      createdAt: now,
    );
    _s.bookings.add(booking);
    _s.idempotency[idempotencyKey] = MockIdempotencyEntry(
      fingerprint: fingerprint,
      bookingId: booking.id,
    );
    await _commit();
    return _withOverlap(booking);
  }

  MockClient _resolveClient(String shopId, StaffBookingRequest r) {
    if (r.clientId != null) {
      final c = _s.clients.where((x) => x.id == r.clientId).firstOrNull;
      if (c == null || !c.fichaNames.containsKey(shopId)) {
        throw _notFound('Cliente');
      }
      return c;
    }
    final name = (r.newClientName ?? '').trim();
    if (name.length < 2 || name.length > 80) {
      throw _invalid('newClient.name', 'Nome com 2 a 80 letras');
    }
    final raw = (r.newClientPhone ?? '').trim();
    if (raw.isEmpty && r.source == BookingSource.staff) {
      throw _invalid('newClient.phone', 'Telefone obrigatório');
    }
    String? phone;
    if (raw.isNotEmpty) {
      phone = normalizePhone(raw);
      if (phone == null) throw _invalid('newClient.phone', 'Telefone inválido');
    }
    return _upsertFicha(shopId, name, phone);
  }

  /// Cliente único por telefone e ficha por barbearia. Sem telefone (balcão):
  /// só uma ficha desta barbearia.
  MockClient _upsertFicha(String shopId, String name, String? phone) {
    final existing = phone == null
        ? null
        : _s.clients.where((c) => c.phone == phone).firstOrNull;
    if (existing != null) {
      existing.fichaNames.putIfAbsent(shopId, () => name);
      return existing;
    }
    final c = MockClient(
      id: newUuid(),
      phone: phone,
      name: name,
      createdAt: clock.now(),
      fichaNames: {shopId: name},
    );
    _s.clients.add(c);
    return c;
  }

  @override
  Future<Booking> changeBookingStatus(
    String token, {
    required String barbershopId,
    required String bookingId,
    required String idempotencyKey,
    required BookingStatus status,
  }) async {
    await _begin('changeBookingStatus');
    final ctx = _ctx(token, barbershopId);
    final i = _s.bookings.indexWhere(
      (b) => b.id == bookingId && b.barbershopId == barbershopId,
    );
    if (i < 0) throw _notFound('Agendamento');
    final b = _s.bookings[i];
    if (!ctx.isManager && b.professional.id != ctx.ownProfessionalId) {
      throw _forbidden;
    }
    final fingerprint = 'status|$bookingId|${status.wire}';
    final seen = _s.idempotency[idempotencyKey];
    if (seen != null) {
      if (seen.fingerprint != fingerprint) {
        throw const ApiProblem(
          ErrorCode.idempotencyKeyReused,
          status: 422,
          title: 'Chave já usada com outro pedido',
        );
      }
      return _withOverlap(b);
    }
    if (status == BookingStatus.scheduled) {
      throw _invalid('status', 'Use COMPLETED, NO_SHOW ou CANCELED');
    }
    if (b.status != BookingStatus.scheduled) {
      throw const ApiProblem(
        ErrorCode.statusChanged,
        status: 409,
        title: 'O status já mudou',
      );
    }
    final now = clock.now();
    if (status != BookingStatus.canceled && now.isBefore(b.startAt)) {
      throw const ApiProblem(
        ErrorCode.tooEarly,
        status: 422,
        title: 'Ainda não começou',
      );
    }
    final Booking updated;
    switch (status) {
      case BookingStatus.completed:
        final split = _c.commission[barbershopId]!.splitFor(b.professional.id);
        updated = b.copyWith(
          status: status,
          shopPercent: split.shopPercent,
          professionalPercent: split.professionalPercent,
        );
      case BookingStatus.canceled:
        updated = b.copyWith(status: status, canceledBy: CanceledBy.staff);
      default:
        updated = b.copyWith(status: status);
    }
    _s.bookings[i] = updated;
    _s.idempotency[idempotencyKey] = MockIdempotencyEntry(
      fingerprint: fingerprint,
      bookingId: bookingId,
    );
    await _commit();
    return _withOverlap(updated);
  }

  @override
  Future<Block> createBlock(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    await _begin('createBlock');
    final ctx = _ctx(token, barbershopId);
    if (!ctx.isManager && professionalId != ctx.ownProfessionalId) {
      throw _forbidden;
    }
    _activePro(barbershopId, professionalId);
    if (!isOnGrid(startAt)) throw _invalid('startAt', 'Fora da grade');
    if (!isOnGrid(endAt)) throw _invalid('endAt', 'Fora da grade');
    if (!endAt.isAfter(startAt)) {
      throw _invalid('endAt', 'O fim tem que ser depois do início');
    }
    // Dentro do mesmo dia; terminar às 00:00 conta como fim do mesmo dia.
    if (endAt.isAfter(SpDate.of(startAt).addDays(1).at(0))) {
      throw _invalid('endAt', 'O bloqueio não atravessa a meia-noite');
    }
    final span = TimeSpan(startAt, endAt);
    if (_blocksOf(
      barbershopId,
      professionalId,
    ).any((b) => b.span.overlaps(span))) {
      throw const ApiProblem(
        ErrorCode.slotTaken,
        status: 409,
        title: 'Já tem bloqueio nesse intervalo',
      );
    }
    final block = MockBlock(
      id: newUuid(),
      barbershopId: barbershopId,
      professionalId: professionalId,
      startAt: startAt,
      endAt: endAt,
    );
    _s.blocks.add(block);
    await _commit();
    return Block(
      id: block.id,
      professionalId: professionalId,
      startAt: startAt,
      endAt: endAt,
    );
  }

  @override
  Future<void> deleteBlock(
    String token, {
    required String barbershopId,
    required String blockId,
  }) async {
    await _begin('deleteBlock');
    final ctx = _ctx(token, barbershopId);
    final b = _s.blocks
        .where((x) => x.id == blockId && x.barbershopId == barbershopId)
        .firstOrNull;
    if (b == null) throw _notFound('Bloqueio');
    if (!ctx.isManager && b.professionalId != ctx.ownProfessionalId) {
      throw _forbidden;
    }
    _s.blocks.remove(b);
    await _commit();
  }

  // ------------------------------------------------------------ equipe

  @override
  Future<List<Professional>> listProfessionals(
    String token, {
    required String barbershopId,
  }) async {
    await _begin('listProfessionals');
    _manager(token, barbershopId);
    return [..._pros(barbershopId)];
  }

  @override
  Future<Professional> updateProfessional(
    String token, {
    required String barbershopId,
    required String professionalId,
    bool? active,
    String? name,
  }) async {
    await _begin('updateProfessional');
    _manager(token, barbershopId);
    final list = _pros(barbershopId);
    final i = list.indexWhere((p) => p.id == professionalId);
    if (i < 0) throw _notFound('Profissional');
    if (name != null && name.trim().isEmpty) {
      throw _invalid('name', 'Nome obrigatório');
    }
    final now = clock.now();
    if (active == false && list[i].active) {
      final hasFuture = _s.bookings.any(
        (b) =>
            b.barbershopId == barbershopId &&
            b.professional.id == professionalId &&
            b.status == BookingStatus.scheduled &&
            b.endAt.isAfter(now),
      );
      if (hasFuture) {
        throw const ApiProblem(
          ErrorCode.professionalHasFutureBookings,
          status: 409,
          title: 'Tem horário futuro',
        );
      }
      _unlink(barbershopId, professionalId);
    } else if (active == true && !list[i].active) {
      _relink(barbershopId, professionalId);
    }
    list[i] = list[i].copyWith(name: name?.trim(), active: active);
    await _commit();
    return list[i];
  }

  /// Desativado como profissional: o gerente continua gerente, sem agenda
  /// própria (`professionalId` = `null`); quem só atende perde o acesso aqui.
  void _unlink(String shopId, String proId) {
    for (final st in _c.staff) {
      for (final m in st.memberships) {
        if (m.barbershopId != shopId || m.professionalId != proId) continue;
        m.formerProfessionalId = proId;
        m.professionalId = null;
        if (m.isManager) {
          m.roles = {StaffRole.manager};
        } else {
          m.active = false;
        }
      }
    }
  }

  void _relink(String shopId, String proId) {
    for (final st in _c.staff) {
      for (final m in st.memberships) {
        if (m.barbershopId != shopId || m.formerProfessionalId != proId) {
          continue;
        }
        m.professionalId = proId;
        m.formerProfessionalId = null;
        m.roles = {...m.roles, StaffRole.professional};
        m.active = true;
      }
    }
  }

  @override
  Future<Map<int, List<WorkWindow>>> getWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
  }) async {
    await _begin('getWorkingHours');
    final ctx = _ctx(token, barbershopId);
    if (!ctx.isManager && professionalId != ctx.ownProfessionalId) {
      throw _forbidden;
    }
    if (!_pros(barbershopId).any((p) => p.id == professionalId)) {
      throw _notFound('Profissional');
    }
    return {...?_c.weeklyHours[professionalId]};
  }

  @override
  Future<Map<int, List<WorkWindow>>> replaceWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
    required Map<int, List<WorkWindow>> days,
  }) async {
    await _begin('replaceWorkingHours');
    _manager(token, barbershopId);
    if (!_pros(barbershopId).any((p) => p.id == professionalId)) {
      throw _notFound('Profissional');
    }
    for (final e in days.entries) {
      if (e.key < 1 || e.key > 7) throw _invalid('days', 'Dia inválido');
      final p = checkDayWindows(e.value, field: 'days[${e.key}].windows');
      if (p != null) throw p;
    }
    _c.weeklyHours[professionalId] = {
      for (final e in days.entries)
        if (e.value.isNotEmpty) e.key: [...e.value],
    };
    await _commit();
    return {..._c.weeklyHours[professionalId]!};
  }

  @override
  Future<TimeOff> createTimeOff(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    await _begin('createTimeOff');
    _manager(token, barbershopId);
    if (!_pros(barbershopId).any((p) => p.id == professionalId)) {
      throw _notFound('Profissional');
    }
    if (!endAt.isAfter(startAt)) {
      throw _invalid('endAt', 'O fim tem que ser depois do início');
    }
    final t = TimeOff(
      id: newUuid(),
      professionalId: professionalId,
      startAt: startAt,
      endAt: endAt,
    );
    _c.timeOff.add(t);
    await _commit();
    return t;
  }

  // ------------------------------------------------------------ serviços

  @override
  Future<List<Service>> activeServices({required String barbershopId}) async {
    await _begin('activeServices');
    return (_c.services[barbershopId] ?? []).where((x) => x.active).toList();
  }

  @override
  Future<List<Service>> listServices(
    String token, {
    required String barbershopId,
  }) async {
    await _begin('listServices');
    _manager(token, barbershopId);
    return [...?_c.services[barbershopId]];
  }

  @override
  Future<Service> updateService(
    String token, {
    required String barbershopId,
    required String serviceId,
    required ServicePatch patch,
  }) async {
    await _begin('updateService');
    _manager(token, barbershopId);
    final list = _c.services[barbershopId] ?? [];
    final i = list.indexWhere((x) => x.id == serviceId);
    if (i < 0) throw _notFound('Serviço');
    if (patch.durationMinutes != null) {
      final p = checkServiceDuration(patch.durationMinutes!);
      if (p != null) throw p;
    }
    if (patch.priceCents != null && patch.priceCents! < 0) {
      throw _invalid('priceCents', 'Preço não pode ser negativo');
    }
    if (patch.name != null && patch.name!.trim().isEmpty) {
      throw _invalid('name', 'Nome obrigatório');
    }
    final old = list[i];
    list[i] = Service(
      id: old.id,
      name: patch.name?.trim() ?? old.name,
      durationMinutes: patch.durationMinutes ?? old.durationMinutes,
      priceCents: patch.priceCents ?? old.priceCents,
      active: patch.active ?? old.active,
    );
    await _commit();
    return list[i];
  }

  // ------------------------------------------------------------ clientes

  ClientFile _file(MockClient c, String shopId) => ClientFile(
    id: c.id,
    name: c.fichaNames[shopId] ?? c.name,
    phone: c.phone,
    hasDevice: _s.codes.containsValue(c.id),
    email: _c.clientEmails['$shopId|${c.id}'],
    createdAt: c.createdAt,
  );

  static String _fold(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const to = 'aaaaaeeeeiiiiooooouuuuc';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString();
  }

  @override
  Future<List<ClientFile>> searchClients(
    String token, {
    required String barbershopId,
    String? q,
  }) async {
    await _begin('searchClients');
    _ctx(token, barbershopId);
    final query = (q ?? '').trim();
    final digits = query.replaceAll(RegExp(r'\D'), '');
    final text = _fold(query);
    final out = <ClientFile>[];
    for (final c in _s.clients) {
      final name = c.fichaNames[barbershopId];
      if (name == null) continue;
      final byName = text.isNotEmpty && _fold(name).contains(text);
      final byPhone = digits.length >= 4 && (c.phone ?? '').contains(digits);
      if (query.isEmpty || byName || byPhone) out.add(_file(c, barbershopId));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out.take(20).toList();
  }

  @override
  Future<ClientFile> createClient(
    String token, {
    required String barbershopId,
    required String name,
    required String phone,
    String? email,
  }) async {
    await _begin('createClient');
    _ctx(token, barbershopId);
    final n = name.trim();
    if (n.length < 2 || n.length > 80) {
      throw _invalid('name', 'Nome com 2 a 80 letras');
    }
    final normalized = normalizePhone(phone);
    if (normalized == null) throw _invalid('phone', 'Telefone inválido');
    final existing = _s.clients.where((c) => c.phone == normalized).firstOrNull;
    if (existing != null && existing.fichaNames.containsKey(barbershopId)) {
      throw const ApiProblem(
        ErrorCode.phoneInUse,
        status: 409,
        title: 'Telefone já cadastrado',
      );
    }
    final c = _upsertFicha(barbershopId, n, normalized);
    if (email != null && email.trim().isNotEmpty) {
      _c.clientEmails['$barbershopId|${c.id}'] = email.trim();
    }
    await _commit();
    return _file(c, barbershopId);
  }

  MockClient _clientAt(String shopId, String clientId) {
    final c = _s.clients.where((x) => x.id == clientId).firstOrNull;
    if (c == null || !c.fichaNames.containsKey(shopId)) {
      throw _notFound('Cliente');
    }
    return c;
  }

  @override
  Future<ClientDetail> getClient(
    String token, {
    required String barbershopId,
    required String clientId,
  }) async {
    await _begin('getClient');
    _ctx(token, barbershopId);
    final c = _clientAt(barbershopId, clientId);
    final recent =
        _s.bookings
            .where((b) => b.barbershopId == barbershopId && b.client.id == c.id)
            .map(_withOverlap)
            .toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return ClientDetail(
      client: _file(c, barbershopId),
      recentBookings: recent.take(10).toList(),
    );
  }

  @override
  Future<ClientFile> updateClient(
    String token, {
    required String barbershopId,
    required String clientId,
    String? name,
    String? phone,
  }) async {
    await _begin('updateClient');
    // Só o gerente edita a ficha; o profissional leva 403 em qualquer ficha.
    _manager(token, barbershopId);
    var c = _clientAt(barbershopId, clientId);
    if (name != null) {
      final n = name.trim();
      if (n.length < 2 || n.length > 80) {
        throw _invalid('name', 'Nome com 2 a 80 letras');
      }
      c.fichaNames[barbershopId] = n;
    }
    if (phone != null) {
      final normalized = normalizePhone(phone);
      if (normalized == null) throw _invalid('phone', 'Telefone inválido');
      if (_s.clients.any((x) => x.phone == normalized && x.id != c.id)) {
        throw const ApiProblem(
          ErrorCode.phoneInUse,
          status: 409,
          title: 'Telefone já cadastrado',
        );
      }
      final i = _s.clients.indexOf(c);
      c = MockClient(
        id: c.id,
        phone: normalized,
        name: c.name,
        createdAt: c.createdAt,
        fichaNames: c.fichaNames,
      );
      _s.clients[i] = c;
    }
    await _commit();
    return _file(c, barbershopId);
  }

  @override
  Future<void> releaseDevice(
    String token, {
    required String barbershopId,
    required String clientId,
  }) async {
    await _begin('releaseDevice');
    _manager(token, barbershopId);
    // Mesma regra do "servidor" do app Cliente (trava DEVICE_RELEASE_NOT_ALLOWED
    // e revogação do código), sobre o mesmo estado.
    await MockClienteRepository(
      clock: clock,
      initialState: _s,
    ).releaseClientDevice(barbershopId: barbershopId, clientId: clientId);
    await _commit();
  }

  // ------------------------------------------------------------ caixa

  static final _monthRe = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  void _checkMonth(String month) {
    if (!_monthRe.hasMatch(month)) {
      throw _invalid('month', 'Use AAAA-MM');
    }
  }

  static String monthOf(DateTime instant) {
    final d = SpDate.of(instant);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}';
  }

  List<Booking> _completedIn(String shopId, String month, [String? proId]) =>
      _s.bookings
          .where(
            (b) =>
                b.barbershopId == shopId &&
                b.status == BookingStatus.completed &&
                (proId == null || b.professional.id == proId) &&
                monthOf(b.startAt) == month,
          )
          .toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));

  CashTotals _sum(Iterable<Booking> list) =>
      list.fold(CashTotals.zero, (t, b) => t.plus(b));

  @override
  Future<MonthlyCash> getCash(
    String token, {
    required String barbershopId,
    required String month,
  }) async {
    await _begin('getCash');
    final ctx = _ctx(token, barbershopId);
    _checkMonth(month);
    if (!ctx.isManager) {
      final own = ctx.ownProfessionalId;
      if (own == null) throw _forbidden;
      final pro = _pros(barbershopId).firstWhere((p) => p.id == own);
      final t = _sum(_completedIn(barbershopId, month, own)).withoutShop;
      return MonthlyCash(
        month: month,
        totals: t,
        byProfessional: [CashRow(professional: pro.public, totals: t)],
      );
    }
    final all = _completedIn(barbershopId, month);
    final rows = <CashRow>[
      for (final p in _pros(barbershopId))
        if (p.active || all.any((b) => b.professional.id == p.id))
          CashRow(
            professional: p.public,
            totals: _sum(all.where((b) => b.professional.id == p.id)),
          ),
    ];
    return MonthlyCash(month: month, totals: _sum(all), byProfessional: rows);
  }

  @override
  Future<ProfessionalCash> getProfessionalCash(
    String token, {
    required String barbershopId,
    required String professionalId,
    required String month,
  }) async {
    await _begin('getProfessionalCash');
    final ctx = _ctx(token, barbershopId);
    if (!ctx.isManager && professionalId != ctx.ownProfessionalId) {
      throw _forbidden;
    }
    _checkMonth(month);
    final pro = _pros(
      barbershopId,
    ).where((p) => p.id == professionalId).firstOrNull;
    if (pro == null) throw _notFound('Profissional');
    final list = _completedIn(barbershopId, month, professionalId);
    final t = _sum(list);
    return ProfessionalCash(
      month: month,
      professional: pro.public,
      totals: ctx.isManager ? t : t.withoutShop,
      bookings: ctx.isManager
          ? list
          : [
              for (final b in list)
                Booking(
                  id: b.id,
                  barbershopId: b.barbershopId,
                  barbershopName: b.barbershopName,
                  status: b.status,
                  source: b.source,
                  startAt: b.startAt,
                  endAt: b.endAt,
                  service: b.service,
                  professional: b.professional,
                  client: b.client,
                  priceCents: b.priceCents,
                  professionalPercent: b.professionalPercent,
                  createdAt: b.createdAt,
                ),
            ],
    );
  }

  @override
  Future<CommissionSettings> getCommission(
    String token, {
    required String barbershopId,
  }) async {
    await _begin('getCommission');
    _manager(token, barbershopId);
    return _c.commission[barbershopId]!;
  }

  @override
  Future<CommissionSettings> replaceCommission(
    String token, {
    required String barbershopId,
    required CommissionSettings settings,
  }) async {
    await _begin('replaceCommission');
    _manager(token, barbershopId);
    final std = settings.standard;
    final p0 = checkSplit(std.shopPercent, std.professionalPercent);
    if (p0 != null) throw p0;
    final ids = _pros(barbershopId).map((p) => p.id).toSet();
    for (final e in settings.professionals.entries) {
      if (!ids.contains(e.key)) {
        throw _invalid('professionals.professionalId', 'Profissional inválido');
      }
      final p = checkSplit(e.value.shopPercent, e.value.professionalPercent);
      if (p != null) throw p;
    }
    _c.commission[barbershopId] = CommissionSettings(
      standard: std,
      professionals: {...settings.professionals},
    );
    await _commit();
    return _c.commission[barbershopId]!;
  }
}
