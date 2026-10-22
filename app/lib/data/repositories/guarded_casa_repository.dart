import '../../core/errors/api_problem.dart';
import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import '../models/staff.dart';
import 'casa_repository.dart';

/// Repassa tudo para [inner] e, quando o servidor (ou o mock) responde 401
/// fora do login, chama [onUnauthorized]: a Casa esquece o login guardado e
/// volta para a tela de entrar (resposta 3 do PO).
class GuardedCasaRepository implements CasaRepository {
  GuardedCasaRepository(this.inner, {required this.onUnauthorized});

  final CasaRepository inner;
  final void Function() onUnauthorized;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiProblem catch (e) {
      if (e.status == 401 || e.code == ErrorCode.unauthorized) {
        onUnauthorized();
      }
      rethrow;
    }
  }

  // Login recusado (401) é senha errada, não sessão vencida: passa direto.
  @override
  Future<StaffSession> login({
    required String email,
    required String password,
  }) => inner.login(email: email, password: password);

  @override
  Future<StaffUser> me(String token) => _guard(() => inner.me(token));

  @override
  Future<void> logout(String token) => _guard(() => inner.logout(token));

  @override
  Future<Agenda> getAgenda(
    String token, {
    required String barbershopId,
    required SpDate date,
    String? professionalId,
  }) => _guard(
    () => inner.getAgenda(
      token,
      barbershopId: barbershopId,
      date: date,
      professionalId: professionalId,
    ),
  );

  @override
  Future<Booking> createStaffBooking(
    String token, {
    required String barbershopId,
    required String idempotencyKey,
    required StaffBookingRequest request,
  }) => _guard(
    () => inner.createStaffBooking(
      token,
      barbershopId: barbershopId,
      idempotencyKey: idempotencyKey,
      request: request,
    ),
  );

  @override
  Future<Booking> changeBookingStatus(
    String token, {
    required String barbershopId,
    required String bookingId,
    required String idempotencyKey,
    required BookingStatus status,
  }) => _guard(
    () => inner.changeBookingStatus(
      token,
      barbershopId: barbershopId,
      bookingId: bookingId,
      idempotencyKey: idempotencyKey,
      status: status,
    ),
  );

  @override
  Future<Block> createBlock(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  }) => _guard(
    () => inner.createBlock(
      token,
      barbershopId: barbershopId,
      professionalId: professionalId,
      startAt: startAt,
      endAt: endAt,
    ),
  );

  @override
  Future<void> deleteBlock(
    String token, {
    required String barbershopId,
    required String blockId,
  }) => _guard(
    () =>
        inner.deleteBlock(token, barbershopId: barbershopId, blockId: blockId),
  );

  @override
  Future<List<Professional>> listProfessionals(
    String token, {
    required String barbershopId,
  }) =>
      _guard(() => inner.listProfessionals(token, barbershopId: barbershopId));

  @override
  Future<Professional> updateProfessional(
    String token, {
    required String barbershopId,
    required String professionalId,
    bool? active,
    String? name,
  }) => _guard(
    () => inner.updateProfessional(
      token,
      barbershopId: barbershopId,
      professionalId: professionalId,
      active: active,
      name: name,
    ),
  );

  @override
  Future<Map<int, List<WorkWindow>>> getWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
  }) => _guard(
    () => inner.getWorkingHours(
      token,
      barbershopId: barbershopId,
      professionalId: professionalId,
    ),
  );

  @override
  Future<Map<int, List<WorkWindow>>> replaceWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
    required Map<int, List<WorkWindow>> days,
  }) => _guard(
    () => inner.replaceWorkingHours(
      token,
      barbershopId: barbershopId,
      professionalId: professionalId,
      days: days,
    ),
  );

  @override
  Future<TimeOff> createTimeOff(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  }) => _guard(
    () => inner.createTimeOff(
      token,
      barbershopId: barbershopId,
      professionalId: professionalId,
      startAt: startAt,
      endAt: endAt,
    ),
  );

  @override
  Future<List<Service>> activeServices({required String barbershopId}) =>
      _guard(() => inner.activeServices(barbershopId: barbershopId));

  @override
  Future<List<Service>> listServices(
    String token, {
    required String barbershopId,
  }) => _guard(() => inner.listServices(token, barbershopId: barbershopId));

  @override
  Future<Service> updateService(
    String token, {
    required String barbershopId,
    required String serviceId,
    required ServicePatch patch,
  }) => _guard(
    () => inner.updateService(
      token,
      barbershopId: barbershopId,
      serviceId: serviceId,
      patch: patch,
    ),
  );

  @override
  Future<List<ClientFile>> searchClients(
    String token, {
    required String barbershopId,
    String? q,
  }) => _guard(
    () => inner.searchClients(token, barbershopId: barbershopId, q: q),
  );

  @override
  Future<ClientFile> createClient(
    String token, {
    required String barbershopId,
    required String name,
    required String phone,
    String? email,
  }) => _guard(
    () => inner.createClient(
      token,
      barbershopId: barbershopId,
      name: name,
      phone: phone,
      email: email,
    ),
  );

  @override
  Future<ClientDetail> getClient(
    String token, {
    required String barbershopId,
    required String clientId,
  }) => _guard(
    () =>
        inner.getClient(token, barbershopId: barbershopId, clientId: clientId),
  );

  @override
  Future<ClientFile> updateClient(
    String token, {
    required String barbershopId,
    required String clientId,
    String? name,
    String? phone,
  }) => _guard(
    () => inner.updateClient(
      token,
      barbershopId: barbershopId,
      clientId: clientId,
      name: name,
      phone: phone,
    ),
  );

  @override
  Future<void> releaseDevice(
    String token, {
    required String barbershopId,
    required String clientId,
  }) => _guard(
    () => inner.releaseDevice(
      token,
      barbershopId: barbershopId,
      clientId: clientId,
    ),
  );

  @override
  Future<MonthlyCash> getCash(
    String token, {
    required String barbershopId,
    required String month,
  }) => _guard(
    () => inner.getCash(token, barbershopId: barbershopId, month: month),
  );

  @override
  Future<ProfessionalCash> getProfessionalCash(
    String token, {
    required String barbershopId,
    required String professionalId,
    required String month,
  }) => _guard(
    () => inner.getProfessionalCash(
      token,
      barbershopId: barbershopId,
      professionalId: professionalId,
      month: month,
    ),
  );

  @override
  Future<CommissionSettings> getCommission(
    String token, {
    required String barbershopId,
  }) => _guard(() => inner.getCommission(token, barbershopId: barbershopId));

  @override
  Future<CommissionSettings> replaceCommission(
    String token, {
    required String barbershopId,
    required CommissionSettings settings,
  }) => _guard(
    () => inner.replaceCommission(
      token,
      barbershopId: barbershopId,
      settings: settings,
    ),
  );
}
