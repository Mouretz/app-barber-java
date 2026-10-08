import '../../core/time/sao_paulo.dart';
import '../models/availability.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';

/// `scope` de `GET /me/bookings`.
enum BookingScope { upcoming, past }

/// Tudo o que o app Cliente pede ao servidor (tag `Cliente` do contrato).
///
/// A tela só conhece esta interface. Hoje roda com [MockClienteRepository]
/// (em memória, sem servidor); quando o servidor subir, entra a versão que
/// chama a API com o mesmo contrato, sem mexer nas telas.
///
/// Erros chegam sempre como `ApiProblem` com o `code` do contrato.
abstract class ClienteRepository {
  /// `GET /barbershops` (história 15).
  Future<List<BarbershopSummary>> listBarbershops({String? q});

  /// `GET /barbershops/{id}` (história 16). Só serviços e profissionais ativos.
  Future<BarbershopDetail> getBarbershop(String barbershopId);

  /// `GET /barbershops/{id}/availability` (história 1).
  Future<Availability> getAvailability({
    required String barbershopId,
    required String serviceId,
    required String professionalId,
    required SpDate date,
  });

  /// `POST /barbershops/{id}/bookings` (história 1).
  ///
  /// [idempotencyKey] vai no cabeçalho `Idempotency-Key`; repetir a chave devolve
  /// o mesmo agendamento. [clientCode] vai em `X-Client-Code` quando o aparelho
  /// já tem código.
  ///
  /// `ClientBookingCreated.clientCode` só vem quando o telefone é novo. Telefone
  /// que já existe, sem código no aparelho, marca o horário mas não recebe código
  /// (só telefone não basta, CT-04-08).
  Future<ClientBookingCreated> createClientBooking({
    required String barbershopId,
    required String idempotencyKey,
    String? clientCode,
    required ClientBookingRequest request,
  });

  /// `GET /me/bookings` (histórias 4 e 15). Próximos em ordem crescente,
  /// passados em ordem decrescente.
  Future<List<Booking>> listMyBookings({
    required String clientCode,
    BookingScope scope = BookingScope.upcoming,
    int limit = 20,
  });

  /// `POST /me/bookings/{id}/cancel` (história 4).
  Future<Booking> cancelMyBooking({
    required String clientCode,
    required String bookingId,
  });
}
