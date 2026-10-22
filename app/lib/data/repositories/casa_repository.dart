import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import '../models/staff.dart';

/// Tudo o que o app Casa pede ao servidor (tags Auth, Agenda, Equipe,
/// Clientes, Serviços e Gerência do contrato). [token] é o `staffToken`.
///
/// A barbearia e o papel valem pelo token: o servidor (e o mock) conferem o
/// vínculo a cada pedido. Erros chegam como `ApiProblem` com o `code` do
/// contrato.
abstract class CasaRepository {
  /// `POST /auth/login`. Senha errada, e-mail desconhecido e profissional
  /// sem vínculo ativo dão o mesmo 401.
  Future<StaffSession> login({required String email, required String password});

  /// `GET /auth/me`.
  Future<StaffUser> me(String token);

  /// `POST /auth/logout`.
  Future<void> logout(String token);

  /// `GET /agenda`. Gerente: todos os ativos ou [professionalId]. Profissional
  /// que não é gerente: só a dele; pedir outro dá 403.
  Future<Agenda> getAgenda(
    String token, {
    required String barbershopId,
    required SpDate date,
    String? professionalId,
  });

  /// `POST /staff/bookings` (marcar pela Casa ou balcão).
  Future<Booking> createStaffBooking(
    String token, {
    required String barbershopId,
    required String idempotencyKey,
    required StaffBookingRequest request,
  });

  /// `POST /staff/bookings/{id}/status`.
  Future<Booking> changeBookingStatus(
    String token, {
    required String barbershopId,
    required String bookingId,
    required String idempotencyKey,
    required BookingStatus status,
  });

  /// `POST /blocks`.
  Future<Block> createBlock(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  });

  /// `DELETE /blocks/{id}`.
  Future<void> deleteBlock(
    String token, {
    required String barbershopId,
    required String blockId,
  });

  /// `GET /professionals` (só gerente, inclui inativos).
  Future<List<Professional>> listProfessionals(
    String token, {
    required String barbershopId,
  });

  /// `PATCH /professionals/{id}` (só gerente). Desativar com horário futuro:
  /// 409 `PROFESSIONAL_HAS_FUTURE_BOOKINGS`.
  Future<Professional> updateProfessional(
    String token, {
    required String barbershopId,
    required String professionalId,
    bool? active,
    String? name,
  });

  /// `GET /working-hours` (weekday 1 = seg ... 7 = dom).
  Future<Map<int, List<WorkWindow>>> getWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
  });

  /// `PUT /working-hours` (só gerente). Troca a semana inteira.
  Future<Map<int, List<WorkWindow>>> replaceWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
    required Map<int, List<WorkWindow>> days,
  });

  /// `POST /time-off` (só gerente). Não apaga marcações.
  Future<TimeOff> createTimeOff(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  });

  /// Serviços ativos para marcar, do `GET /barbershops/{id}` público (o
  /// profissional não tem `/services`).
  Future<List<Service>> activeServices({required String barbershopId});

  /// `GET /services` (só gerente, inclui inativos).
  Future<List<Service>> listServices(
    String token, {
    required String barbershopId,
  });

  /// `PATCH /services/{id}` (só gerente).
  Future<Service> updateService(
    String token, {
    required String barbershopId,
    required String serviceId,
    required ServicePatch patch,
  });

  /// `GET /clients?q=` (gerente e profissional).
  Future<List<ClientFile>> searchClients(
    String token, {
    required String barbershopId,
    String? q,
  });

  /// `POST /clients` (gerente e profissional).
  Future<ClientFile> createClient(
    String token, {
    required String barbershopId,
    required String name,
    required String phone,
    String? email,
  });

  /// `GET /clients/{id}`.
  Future<ClientDetail> getClient(
    String token, {
    required String barbershopId,
    required String clientId,
  });

  /// `PATCH /clients/{id}` (só gerente; profissional leva 403).
  Future<ClientFile> updateClient(
    String token, {
    required String barbershopId,
    required String clientId,
    String? name,
    String? phone,
  });

  /// `POST /clients/{id}/release-device` (só gerente).
  Future<void> releaseDevice(
    String token, {
    required String barbershopId,
    required String clientId,
  });

  /// `GET /cash?month=AAAA-MM`.
  Future<MonthlyCash> getCash(
    String token, {
    required String barbershopId,
    required String month,
  });

  /// `GET /cash/professionals/{id}?month=AAAA-MM`.
  Future<ProfessionalCash> getProfessionalCash(
    String token, {
    required String barbershopId,
    required String professionalId,
    required String month,
  });

  /// `GET /commission` (só gerente).
  Future<CommissionSettings> getCommission(
    String token, {
    required String barbershopId,
  });

  /// `PUT /commission` (só gerente). Troca a lista inteira.
  Future<CommissionSettings> replaceCommission(
    String token, {
    required String barbershopId,
    required CommissionSettings settings,
  });
}
