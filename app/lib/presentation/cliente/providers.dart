import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/errors/api_problem.dart';
import '../../core/storage/device_store.dart';
import '../../core/time/clock.dart';
import '../../core/time/sao_paulo.dart';
import '../../data/mock/mock_cliente_repository.dart';
import '../../data/mock/mock_persistence.dart';
import '../../data/models/availability.dart';
import '../../data/models/barbershop.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/api_cliente_repository.dart';
import '../../data/repositories/cliente_repository.dart';

/// Relógio do app. Nos testes entra um `FixedClock`.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Repositório do app Cliente. `DATA_SOURCE=mock` (padrão) roda sem servidor.
final clienteRepositoryProvider = Provider<ClienteRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isMock) {
    return MockClienteRepository(
      clock: ref.watch(clockProvider),
      persistence: PrefsMockPersistence(),
      latency: const Duration(milliseconds: 250),
    );
  }
  return ApiClienteRepository(Dio(BaseOptions(baseUrl: config.apiBaseUrl)));
});

final barbershopsProvider = FutureProvider.autoDispose<List<BarbershopSummary>>(
  (ref) => ref.watch(clienteRepositoryProvider).listBarbershops(),
);

final barbershopProvider = FutureProvider.autoDispose
    .family<BarbershopDetail, String>(
      (ref, id) => ref.watch(clienteRepositoryProvider).getBarbershop(id),
    );

/// Horários do aparelho. Sem aparelho preso a um telefone (nunca teve
/// agendamento aceito) volta lista vazia, sem chamar o servidor. Código
/// revogado (troca de celular) dá `UNAUTHORIZED`: o aparelho volta ao estado
/// sem código e a lista fica vazia, sem tela de erro.
final myBookingsProvider = FutureProvider.autoDispose
    .family<List<Booking>, BookingScope>((ref, scope) async {
      final code = ref.watch(
        deviceStoreProvider.select((s) => s.hasSession ? s.clientCode : null),
      );
      if (code == null) return const [];
      try {
        return await ref
            .watch(clienteRepositoryProvider)
            .listMyBookings(clientCode: code, scope: scope);
      } on ApiProblem catch (e) {
        if (e.code == ErrorCode.unauthorized) {
          await ref.read(deviceStoreProvider.notifier).clearSession();
          return const [];
        }
        rethrow;
      }
    });

/// Card "próximo horário" do Início: o primeiro agendado que ainda não passou.
final nextBookingProvider = FutureProvider.autoDispose<Booking?>((ref) async {
  final list = await ref.watch(
    myBookingsProvider(BookingScope.upcoming).future,
  );
  for (final b in list) {
    if (b.status == BookingStatus.scheduled) return b;
  }
  return null;
});

typedef AvailabilityQuery = ({
  String barbershopId,
  String serviceId,
  String professionalId,
  SpDate date,
});

final availabilityProvider = FutureProvider.autoDispose
    .family<Availability, AvailabilityQuery>(
      (ref, q) => ref
          .watch(clienteRepositoryProvider)
          .getAvailability(
            barbershopId: q.barbershopId,
            serviceId: q.serviceId,
            professionalId: q.professionalId,
            date: q.date,
          ),
    );
