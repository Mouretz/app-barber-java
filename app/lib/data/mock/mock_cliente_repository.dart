import '../../core/errors/api_problem.dart';
import '../../core/ids/uuid.dart';
import '../../core/phone/phone.dart';
import '../../core/time/clock.dart';
import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/availability.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import '../repositories/cliente_repository.dart';
import 'mock_persistence.dart';
import 'mock_seed.dart';
import 'mock_state.dart';

/// Repositório do app Cliente sem servidor. Aplica as mesmas recusas que o
/// servidor vai aplicar (CT-00-36), com os mesmos códigos de erro do contrato,
/// para o comportamento não mudar quando o app ligar na API.
class MockClienteRepository implements ClienteRepository {
  MockClienteRepository({
    required this.clock,
    MockPersistence? persistence,
    MockState? initialState,
    this.latency = Duration.zero,
  }) : _persistence = persistence ?? MemoryMockPersistence(),
       _state = initialState;

  final Clock clock;
  final Duration latency;
  final MockPersistence _persistence;
  MockState? _state;
  Future<MockState>? _loading;

  /// Estado atual (para testes montarem cenários).
  Future<MockState> get state => _ensureState();

  Future<MockState> _ensureState() {
    if (_state != null) return Future.value(_state);
    return _loading ??= () async {
      final shops = MockSeed.shops();
      final saved = await _persistence.load();
      final restored = saved == null ? null : MockState.fromJson(shops, saved);
      final s = restored ?? MockSeed.build(clock.now());
      _state = s;
      if (restored == null) await _persistence.save(s.toJson());
      return s;
    }();
  }

  Future<MockState> _begin() async {
    final s = await _ensureState();
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return s;
  }

  Future<void> _commit(MockState s) => _persistence.save(s.toJson());

  // ------------------------------------------------------------ leitura

  @override
  Future<List<BarbershopSummary>> listBarbershops({String? q}) async {
    final s = await _begin();
    final term = q?.trim().toLowerCase() ?? '';
    return [
      for (final shop in s.shops)
        if (term.isEmpty ||
            shop.detail.name.toLowerCase().contains(term) ||
            shop.detail.neighborhood.toLowerCase().contains(term))
          BarbershopSummary(
            id: shop.detail.id,
            name: shop.detail.name,
            neighborhood: shop.detail.neighborhood,
            city: shop.detail.city,
            coverUrl: shop.detail.coverUrl,
            startingPriceCents: _startingPrice(shop.detail),
          ),
    ];
  }

  @override
  Future<BarbershopDetail> getBarbershop(String barbershopId) async {
    final s = await _begin();
    final d = _shop(s, barbershopId).detail;
    return BarbershopDetail(
      id: d.id,
      name: d.name,
      neighborhood: d.neighborhood,
      city: d.city,
      coverUrl: d.coverUrl,
      startingPriceCents: _startingPrice(d),
      address: d.address,
      phone: d.phone,
      services: d.services.where((x) => x.active).toList(),
      professionals: d.professionals,
    );
  }

  @override
  Future<Availability> getAvailability({
    required String barbershopId,
    required String serviceId,
    required String professionalId,
    required SpDate date,
  }) async {
    final s = await _begin();
    final shop = _shop(s, barbershopId);
    final service = _service(shop, serviceId);
    _professional(shop, professionalId);
    final now = clock.now();
    if (!isWithinHorizon(date, now)) {
      throw const ApiProblem(
        ErrorCode.dateOutOfRange,
        status: 422,
        title: 'Fora dos 14 dias',
      );
    }
    final slots = computeFreeSlots(
      date: date,
      now: now,
      durationMinutes: service.durationMinutes,
      windows: shop.windowsFor(professionalId, date),
      busy: _busy(s, barbershopId, professionalId),
    );
    return Availability(
      date: date,
      professionalId: professionalId,
      serviceId: serviceId,
      slots: slots,
    );
  }

  @override
  Future<List<Booking>> listMyBookings({
    required String clientCode,
    BookingScope scope = BookingScope.upcoming,
    int limit = 20,
  }) async {
    final s = await _begin();
    final client = _clientByCode(s, clientCode);
    final now = clock.now();
    final mine = s.bookings.where((b) => b.client.id == client.id);
    final List<Booking> list;
    if (scope == BookingScope.upcoming) {
      list = mine.where((b) => _isUpcoming(b, now)).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
    } else {
      list = mine.where((b) => !_isUpcoming(b, now)).toList()
        ..sort((a, b) => b.startAt.compareTo(a.startAt));
    }
    return list.take(limit).map((b) => _forClient(b, now)).toList();
  }

  // ------------------------------------------------------------ escrita

  @override
  Future<ClientBookingCreated> createClientBooking({
    required String barbershopId,
    required String idempotencyKey,
    String? clientCode,
    required ClientBookingRequest request,
  }) async {
    final s = await _begin();
    // Daqui para baixo é tudo síncrono: dois pedidos nunca se intercalam.
    final now = clock.now();

    final phone = request.client == null
        ? null
        : normalizePhone(request.client!.phone);
    final fingerprint = [
      barbershopId,
      request.serviceId,
      request.professionalId,
      request.startAt.toUtc().toIso8601String(),
      clientCode ?? '',
      phone ?? request.client?.phone ?? '',
    ].join('|');

    // Pedido repetido: mesma chave devolve a mesma resposta.
    final previous = s.idempotency[idempotencyKey];
    if (previous != null) {
      if (previous.fingerprint != fingerprint) {
        throw const ApiProblem(
          ErrorCode.idempotencyKeyReused,
          status: 422,
          title: 'Chave já usada com outro pedido',
        );
      }
      final b = s.bookings.firstWhere((x) => x.id == previous.bookingId);
      return ClientBookingCreated(
        booking: _forClient(b, now),
        clientCode: previous.clientCode,
      );
    }

    final shop = _shop(s, barbershopId);
    final service = _service(shop, request.serviceId);
    final professional = _professional(shop, request.professionalId);

    // Quem está marcando.
    MockClient? client;
    String? issuedCode;
    if (clientCode != null) {
      client = _clientByCode(s, clientCode);
    } else {
      final info = request.client;
      final fields = <ProblemField>[];
      final name = info?.name.trim() ?? '';
      if (name.length < 2 || name.length > 80) {
        fields.add(const ProblemField('name', 'Nome com 2 a 80 letras'));
      }
      if (phone == null) {
        fields.add(const ProblemField('phone', 'Telefone inválido'));
      }
      if (fields.isNotEmpty) {
        throw ApiProblem(
          ErrorCode.validationError,
          status: 422,
          title: 'Dados inválidos',
          fields: fields,
        );
      }
      client = s.clients.where((c) => c.phone == phone).firstOrNull;
    }

    final start = request.startAt.toUtc();
    final date = SpDate.of(start);
    if (!isOnGrid(start)) {
      throw const ApiProblem(
        ErrorCode.validationError,
        status: 422,
        title: 'Fora da grade de 30 minutos',
        fields: [ProblemField('startAt', 'Use :00 ou :30')],
      );
    }
    if (!isWithinHorizon(date, now)) {
      throw const ApiProblem(
        ErrorCode.dateOutOfRange,
        status: 422,
        title: 'Fora dos 14 dias',
      );
    }
    if (!hasMinLead(start, now)) {
      throw const ApiProblem(
        ErrorCode.tooSoon,
        status: 422,
        title: 'Menos de 30 minutos de antecedência',
      );
    }
    if (!fitsWorkingHours(
      start,
      service.durationMinutes,
      shop.windowsFor(professional.id, date),
    )) {
      throw const ApiProblem(
        ErrorCode.outsideWorkingHours,
        status: 422,
        title: 'Fora do expediente',
      );
    }

    // Limite de 2 futuros pelo app, somando todas as barbearias.
    if (client != null) {
      final id = client.id;
      final count = s.bookings
          .where((b) => b.client.id == id && countsForClientLimit(b, now))
          .length;
      if (count >= SchedulingRules.maxFutureClientBookings) {
        throw const ApiProblem(
          ErrorCode.bookingLimitReached,
          status: 422,
          title: 'Limite de 2 horários',
        );
      }
    }

    if (overlapsBusy(
      start,
      service.durationMinutes,
      _busy(s, barbershopId, professional.id),
    )) {
      throw const ApiProblem(
        ErrorCode.slotTaken,
        status: 409,
        title: 'Horário ocupado',
      );
    }

    // Grava.
    if (client == null) {
      client = MockClient(
        id: newUuid(),
        phone: phone!,
        name: request.client!.name.trim(),
        createdAt: now,
      );
      s.clients.add(client);
    }
    client.fichaNames.putIfAbsent(
      barbershopId,
      () => request.client?.name.trim() ?? client!.name,
    );
    if (clientCode == null) {
      issuedCode = s.codes.entries
          .where((e) => e.value == client!.id)
          .map((e) => e.key)
          .firstOrNull;
      if (issuedCode == null) {
        issuedCode = newClientCode();
        s.codes[issuedCode] = client.id;
      }
    }

    final booking = Booking(
      id: newUuid(),
      barbershopId: barbershopId,
      barbershopName: shop.detail.name,
      status: BookingStatus.scheduled,
      source: BookingSource.clientApp,
      startAt: start,
      endAt: start.add(Duration(minutes: service.durationMinutes)),
      service: BookingServiceRef(id: service.id, name: service.name),
      professional: professional,
      client: BookingClientRef(
        id: client.id,
        name: client.fichaNames[barbershopId] ?? client.name,
        phone: client.phone,
      ),
      priceCents: service.priceCents,
      createdAt: now,
    );
    s.bookings.add(booking);
    s.idempotency[idempotencyKey] = MockIdempotencyEntry(
      fingerprint: fingerprint,
      bookingId: booking.id,
      clientCode: issuedCode,
    );
    await _commit(s);
    return ClientBookingCreated(
      booking: _forClient(booking, now),
      clientCode: issuedCode,
    );
  }

  @override
  Future<Booking> cancelMyBooking({
    required String clientCode,
    required String bookingId,
  }) async {
    final s = await _begin();
    final client = _clientByCode(s, clientCode);
    final now = clock.now();
    final i = s.bookings.indexWhere(
      (b) => b.id == bookingId && b.client.id == client.id,
    );
    if (i < 0) {
      throw const ApiProblem(
        ErrorCode.notFound,
        status: 404,
        title: 'Agendamento não encontrado',
      );
    }
    final b = s.bookings[i];
    if (b.status == BookingStatus.canceled &&
        b.canceledBy == CanceledBy.client) {
      return _forClient(b, now); // repetir o cancelamento devolve igual
    }
    if (b.status != BookingStatus.scheduled) {
      throw const ApiProblem(
        ErrorCode.invalidStatusTransition,
        status: 422,
        title: 'O status mudou',
      );
    }
    if (!clientCanCancel(b, now)) {
      throw const ApiProblem(
        ErrorCode.cancelWindowClosed,
        status: 422,
        title: 'Menos de 2 horas',
      );
    }
    final canceled = b.copyWith(
      status: BookingStatus.canceled,
      canceledBy: CanceledBy.client,
    );
    s.bookings[i] = canceled;
    await _commit(s);
    return _forClient(canceled, now);
  }

  // ------------------------------------------------------------ apoio

  static int? _startingPrice(BarbershopDetail d) {
    final prices = d.services.where((x) => x.active).map((x) => x.priceCents);
    if (prices.isEmpty) return null;
    return prices.reduce((a, b) => a < b ? a : b);
  }

  MockShop _shop(MockState s, String id) {
    for (final shop in s.shops) {
      if (shop.detail.id == id) return shop;
    }
    throw const ApiProblem(
      ErrorCode.notFound,
      status: 404,
      title: 'Barbearia não encontrada',
    );
  }

  Service _service(MockShop shop, String id) {
    for (final x in shop.detail.services) {
      if (x.id == id && x.active) return x;
    }
    throw const ApiProblem(
      ErrorCode.notFound,
      status: 404,
      title: 'Serviço não encontrado',
    );
  }

  ProfessionalPublic _professional(MockShop shop, String id) {
    for (final p in shop.detail.professionals) {
      if (p.id == id) return p;
    }
    throw const ApiProblem(
      ErrorCode.notFound,
      status: 404,
      title: 'Profissional não encontrado',
    );
  }

  MockClient _clientByCode(MockState s, String code) {
    final id = s.codes[code];
    final client = id == null
        ? null
        : s.clients.where((c) => c.id == id).firstOrNull;
    if (client == null) {
      throw const ApiProblem(
        ErrorCode.unauthorized,
        status: 401,
        title: 'Código do cliente inválido',
      );
    }
    return client;
  }

  List<TimeSpan> _busy(MockState s, String shopId, String professionalId) =>
      busySpans(
        bookings: s.bookings.where(
          (b) =>
              b.barbershopId == shopId && b.professional.id == professionalId,
        ),
        blocks: s.blocks
            .where(
              (x) =>
                  x.barbershopId == shopId &&
                  x.professionalId == professionalId,
            )
            .map((x) => x.span),
      );

  /// Próximo = agendado e ainda não terminou. Cancelado, falta e concluído vão
  /// para o histórico.
  static bool _isUpcoming(Booking b, DateTime now) =>
      b.status == BookingStatus.scheduled && b.endAt.isAfter(now);

  /// O que o app Cliente recebe: sem telefone, sem nota interna e com
  /// `canCancel` calculado agora.
  static Booking _forClient(Booking b, DateTime now) => Booking(
    id: b.id,
    barbershopId: b.barbershopId,
    barbershopName: b.barbershopName,
    status: b.status,
    source: b.source,
    startAt: b.startAt,
    endAt: b.endAt,
    service: b.service,
    professional: b.professional,
    client: BookingClientRef(id: b.client.id, name: b.client.name),
    priceCents: b.priceCents,
    canCancel: clientCanCancel(b, now),
    canceledBy: b.canceledBy,
    createdAt: b.createdAt,
  );
}
