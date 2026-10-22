import 'package:dio/dio.dart';

import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import '../models/staff.dart';
import 'casa_repository.dart';

/// Versão que fala com o servidor. Fica para o PR que liga a Casa na API; o
/// build de hoje é mock (`DATA_SOURCE=mock`), então nada aqui é chamado.
class ApiCasaRepository implements CasaRepository {
  ApiCasaRepository(this.dio);

  final Dio dio;

  Never _todo() =>
      throw UnimplementedError('Modo API ainda não ligado (próximo PR).');

  @override
  Future<StaffSession> login({
    required String email,
    required String password,
  }) async => _todo();

  @override
  Future<StaffUser> me(String token) async => _todo();

  @override
  Future<void> logout(String token) async => _todo();

  @override
  Future<Agenda> getAgenda(
    String token, {
    required String barbershopId,
    required SpDate date,
    String? professionalId,
  }) async => _todo();

  @override
  Future<Booking> createStaffBooking(
    String token, {
    required String barbershopId,
    required String idempotencyKey,
    required StaffBookingRequest request,
  }) async => _todo();

  @override
  Future<Booking> changeBookingStatus(
    String token, {
    required String barbershopId,
    required String bookingId,
    required String idempotencyKey,
    required BookingStatus status,
  }) async => _todo();

  @override
  Future<Block> createBlock(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  }) async => _todo();

  @override
  Future<void> deleteBlock(
    String token, {
    required String barbershopId,
    required String blockId,
  }) async => _todo();

  @override
  Future<List<Professional>> listProfessionals(
    String token, {
    required String barbershopId,
  }) async => _todo();

  @override
  Future<Professional> updateProfessional(
    String token, {
    required String barbershopId,
    required String professionalId,
    bool? active,
    String? name,
  }) async => _todo();

  @override
  Future<Map<int, List<WorkWindow>>> getWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
  }) async => _todo();

  @override
  Future<Map<int, List<WorkWindow>>> replaceWorkingHours(
    String token, {
    required String barbershopId,
    required String professionalId,
    required Map<int, List<WorkWindow>> days,
  }) async => _todo();

  @override
  Future<TimeOff> createTimeOff(
    String token, {
    required String barbershopId,
    required String professionalId,
    required DateTime startAt,
    required DateTime endAt,
  }) async => _todo();

  @override
  Future<List<Service>> activeServices({required String barbershopId}) async =>
      _todo();

  @override
  Future<List<Service>> listServices(
    String token, {
    required String barbershopId,
  }) async => _todo();

  @override
  Future<Service> updateService(
    String token, {
    required String barbershopId,
    required String serviceId,
    required ServicePatch patch,
  }) async => _todo();

  @override
  Future<List<ClientFile>> searchClients(
    String token, {
    required String barbershopId,
    String? q,
  }) async => _todo();

  @override
  Future<ClientFile> createClient(
    String token, {
    required String barbershopId,
    required String name,
    required String phone,
    String? email,
  }) async => _todo();

  @override
  Future<ClientDetail> getClient(
    String token, {
    required String barbershopId,
    required String clientId,
  }) async => _todo();

  @override
  Future<ClientFile> updateClient(
    String token, {
    required String barbershopId,
    required String clientId,
    String? name,
    String? phone,
  }) async => _todo();

  @override
  Future<void> releaseDevice(
    String token, {
    required String barbershopId,
    required String clientId,
  }) async => _todo();

  @override
  Future<MonthlyCash> getCash(
    String token, {
    required String barbershopId,
    required String month,
  }) async => _todo();

  @override
  Future<ProfessionalCash> getProfessionalCash(
    String token, {
    required String barbershopId,
    required String professionalId,
    required String month,
  }) async => _todo();

  @override
  Future<CommissionSettings> getCommission(
    String token, {
    required String barbershopId,
  }) async => _todo();

  @override
  Future<CommissionSettings> replaceCommission(
    String token, {
    required String barbershopId,
    required CommissionSettings settings,
  }) async => _todo();
}
