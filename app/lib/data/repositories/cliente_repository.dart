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

  /// `POST /barbershops/{id}/bookings` (história 1). Devolve o `Booking`.
  ///
  /// [idempotencyKey] vai no cabeçalho `Idempotency-Key`; repetir a chave devolve
  /// o mesmo agendamento. [clientCode] vai sempre em `X-Client-Code`: o app gera
  /// o código (UUID v4) e ele só fica preso ao telefone quando o agendamento
  /// entra; recusa não prende nada. A resposta nunca traz código.
  ///
  /// Recusas do aparelho:
  /// - telefone preso a outro aparelho: 409 `PHONE_ON_OTHER_DEVICE` (CT-04-15);
  /// - código preso a outro telefone: 409 `DEVICE_PHONE_MISMATCH`;
  /// - código liberado pelo gerente (troca de celular): 401 `UNAUTHORIZED`.
  ///
  /// `X-Client-Code` ausente (aqui, string vazia), fora do formato UUID,
  /// desconhecido onde precisa existir (listar, cancelar) ou liberado: sempre o
  /// mesmo 401 `UNAUTHORIZED`, conferido antes de qualquer outra regra.
  Future<Booking> createClientBooking({
    required String barbershopId,
    required String idempotencyKey,
    required String clientCode,
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
  ///
  /// [idempotencyKey] vai em `Idempotency-Key`: a mesma chave repetida devolve
  /// o mesmo resultado (CT-00-06). Com outra chave, se o status já mudou, o erro
  /// é `STATUS_CHANGED` (CT-04-10, CT-00-44).
  Future<Booking> cancelMyBooking({
    required String clientCode,
    required String bookingId,
    required String idempotencyKey,
  });
}
