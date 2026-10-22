import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/time/sao_paulo.dart';
import '../../data/mock/mock_casa_repository.dart';
import '../../data/mock/mock_persistence.dart';
import '../../data/models/barbershop.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/api_casa_repository.dart';
import '../../data/repositories/casa_repository.dart';
import '../cliente/providers.dart' show clockProvider;

export '../cliente/providers.dart' show clockProvider;

/// Repositório do app Casa. `DATA_SOURCE=mock` roda sem servidor.
final casaRepositoryProvider = Provider<CasaRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.isMock) {
    return MockCasaRepository(
      clock: ref.watch(clockProvider),
      persistence: PrefsMockPersistence(key: PrefsMockPersistence.kCasaKey),
      latency: const Duration(milliseconds: 250),
    );
  }
  return ApiCasaRepository(Dio(BaseOptions(baseUrl: config.apiBaseUrl)));
});

/// Quem entrou e em qual barbearia está agindo.
class CasaSession {
  const CasaSession({
    required this.token,
    required this.user,
    required this.membership,
  });

  final String token;
  final StaffUser user;
  final Membership membership;

  String get shopId => membership.barbershopId;
  bool get isManager => membership.isManager;

  /// Agenda própria: só quem atende. Gerente com `professionalId` `null` não
  /// tem "minha agenda" nem "meus ganhos".
  String? get ownProfessionalId =>
      membership.attends ? membership.professionalId : null;
}

class SessionNotifier extends StateNotifier<CasaSession?> {
  SessionNotifier(this._ref) : super(null);

  final Ref _ref;

  Future<void> login(String email, String password) async {
    final s = await _ref
        .read(casaRepositoryProvider)
        .login(email: email, password: password);
    // MVP: uma barbearia por vez; abre a primeira com vínculo ativo.
    state = CasaSession(
      token: s.accessToken,
      user: s.user,
      membership: s.user.memberships.first,
    );
  }

  /// Relê o `/auth/me` (papel pode ter mudado, ex.: desativado como
  /// profissional). Vínculo perdido aqui ou 401: volta pro login.
  Future<void> refresh() async {
    final cur = state;
    if (cur == null) return;
    try {
      final me = await _ref.read(casaRepositoryProvider).me(cur.token);
      final m = me.membershipAt(cur.shopId);
      state = m == null
          ? null
          : CasaSession(token: cur.token, user: me, membership: m);
    } catch (_) {
      state = null;
    }
  }

  Future<void> logout() async {
    final cur = state;
    state = null;
    if (cur == null) return;
    try {
      await _ref.read(casaRepositoryProvider).logout(cur.token);
    } catch (_) {}
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, CasaSession?>(
  (ref) => SessionNotifier(ref),
);

CasaSession _session(Ref ref) {
  final s = ref.watch(sessionProvider);
  if (s == null) throw StateError('sem sessão');
  return s;
}

typedef AgendaQuery = ({SpDate date, String? professionalId});

/// Agenda do dia. Gerente: todos os ativos (o seletor de profissional vem
/// daqui, só ativos). Profissional: só a dele.
final agendaProvider = FutureProvider.autoDispose.family<Agenda, AgendaQuery>((
  ref,
  q,
) {
  final s = _session(ref);
  return ref
      .watch(casaRepositoryProvider)
      .getAgenda(
        s.token,
        barbershopId: s.shopId,
        date: q.date,
        professionalId: s.isManager ? q.professionalId : null,
      );
});

final cashProvider = FutureProvider.autoDispose.family<MonthlyCash, String>((
  ref,
  month,
) {
  final s = _session(ref);
  return ref
      .watch(casaRepositoryProvider)
      .getCash(s.token, barbershopId: s.shopId, month: month);
});

final clientSearchProvider = FutureProvider.autoDispose
    .family<List<ClientFile>, String>((ref, q) {
      final s = _session(ref);
      return ref
          .watch(casaRepositoryProvider)
          .searchClients(s.token, barbershopId: s.shopId, q: q);
    });

final clientDetailProvider = FutureProvider.autoDispose
    .family<ClientDetail, String>((ref, id) {
      final s = _session(ref);
      return ref
          .watch(casaRepositoryProvider)
          .getClient(s.token, barbershopId: s.shopId, clientId: id);
    });

/// Lista de gestão (só gerente): inclui inativos.
final professionalsProvider = FutureProvider.autoDispose<List<Professional>>((
  ref,
) {
  final s = _session(ref);
  return ref
      .watch(casaRepositoryProvider)
      .listProfessionals(s.token, barbershopId: s.shopId);
});

final activeServicesProvider = FutureProvider.autoDispose<List<Service>>((ref) {
  final s = _session(ref);
  return ref
      .watch(casaRepositoryProvider)
      .activeServices(barbershopId: s.shopId);
});

String monthKey(SpDate d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
