import 'package:dio/dio.dart';

import '../../core/time/sao_paulo.dart';
import '../models/availability.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import 'cliente_repository.dart';

/// Versão que fala com o servidor. Fica para o PR que liga o app na API, quando
/// o Back-end subir os endpoints da tag `Cliente`. O build de hoje é sempre mock
/// (`DATA_SOURCE=mock`), então nada aqui é chamado.
class ApiClienteRepository implements ClienteRepository {
  ApiClienteRepository(this.dio);

  final Dio dio;

  Never _todo() =>
      throw UnimplementedError('Modo API ainda não ligado (próximo PR).');

  @override
  Future<List<BarbershopSummary>> listBarbershops({String? q}) async => _todo();

  @override
  Future<BarbershopDetail> getBarbershop(String barbershopId) async => _todo();

  @override
  Future<Availability> getAvailability({
    required String barbershopId,
    required String serviceId,
    required String professionalId,
    required SpDate date,
  }) async => _todo();

  @override
  Future<ClientBookingCreated> createClientBooking({
    required String barbershopId,
    required String idempotencyKey,
    String? clientCode,
    required ClientBookingRequest request,
  }) async => _todo();

  @override
  Future<List<Booking>> listMyBookings({
    required String clientCode,
    BookingScope scope = BookingScope.upcoming,
    int limit = 20,
  }) async => _todo();

  @override
  Future<Booking> cancelMyBooking({
    required String clientCode,
    required String bookingId,
  }) async => _todo();
}
