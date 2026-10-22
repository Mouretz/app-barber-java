import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/api_problem.dart';

import '../../app.dart';
import '../../core/time/sao_paulo.dart';
import '../../data/mock/mock_casa_repository.dart';
import '../../data/mock/mock_persistence.dart';
import '../../data/models/barbershop.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/api_casa_repository.dart';
import '../../data/repositories/casa_repository.dart';
import '../../data/repositories/guarded_casa_repository.dart';
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

/// O que as telas usam: o mesmo repositório, mas qualquer 401 fora do login
/// esquece o login guardado e volta pra tela de entrar (resposta 3 do PO).
final casaApiProvider = Provider<CasaRepository>(
  (ref) => GuardedCasaRepository(
    ref.watch(casaRepositoryProvider),
    onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
  ),
);

/// Já leu o login guardado no aparelho. Até lá a Casa mostra só o carregando
/// (sem piscar a tela de login).
final casaSessionRestoredProvider = StateProvider<bool>((ref) => false);

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

  Map<String, dynamic> toJson() => {
    'token': token,
    'user': user.toJson(),
    'shopId': shopId,
  };

  /// `null` se o que está guardado não fecha (vínculo sumiu, formato velho).
  static CasaSession? fromJson(Map<String, dynamic> j) {
    final user = StaffUser.fromJson((j['user'] as Map).cast<String, dynamic>());
    final m = user.membershipAt(j['shopId'] as String);
    if (m == null) return null;
    return CasaSession(token: j['token'] as String, user: user, membership: m);
  }
}

/// Login da Casa. Fica guardado no aparelho (chave própria da Casa, separada
/// das do app Cliente) até a pessoa sair ou o servidor responder 401.
class SessionNotifier extends StateNotifier<CasaSession?> {
  SessionNotifier(this._ref) : super(null) {
    unawaited(_restore());
  }

  static const kSession = 'cortaaqui.casa.session';

  final Ref _ref;

  CasaRepository get _api => _ref.read(casaApiProvider);

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kSession);
      if (raw != null) {
        CasaSession? saved;
        try {
          saved = CasaSession.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>(),
          );
        } catch (_) {
          saved = null;
        }
        if (saved == null) {
          await prefs.remove(kSession);
        } else if (state == null) {
          state = saved;
        }
      }
    } catch (_) {
      // Sem acesso ao armazenamento: segue sem login guardado.
    }
    if (mounted) _ref.read(casaSessionRestoredProvider.notifier).state = true;
    // Confere no servidor se o token ainda vale (401 limpa e volta pro login).
    if (mounted && state != null) await refresh();
  }

  Future<void> _save(CasaSession? s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (s == null) {
        await prefs.remove(kSession);
      } else {
        await prefs.setString(kSession, jsonEncode(s.toJson()));
      }
    } catch (_) {}
  }

  void _set(CasaSession? s) {
    if (!mounted) return;
    state = s;
    unawaited(_save(s));
  }

  Future<void> login(String email, String password) async {
    final s = await _api.login(email: email, password: password);
    // MVP: uma barbearia por vez; abre a primeira com vínculo ativo.
    _set(
      CasaSession(
        token: s.accessToken,
        user: s.user,
        membership: s.user.memberships.first,
      ),
    );
  }

  /// Relê o `/auth/me` (papel pode ter mudado, ex.: desativado como
  /// profissional). Vínculo perdido aqui ou 401: volta pro login. Sem rede ou
  /// outro erro: mantém o login guardado.
  Future<void> refresh() async {
    final cur = state;
    if (cur == null) return;
    try {
      final me = await _api.me(cur.token);
      if (state?.token != cur.token) return;
      final m = me.membershipAt(cur.shopId);
      _set(
        m == null
            ? null
            : CasaSession(token: cur.token, user: me, membership: m),
      );
    } on ApiProblem catch (e) {
      if (e.status == 401 || e.status == 403 || e.status == 404) _set(null);
    } catch (_) {}
  }

  /// Servidor respondeu 401: esquece o login e volta pra tela de entrar.
  void expire() => _set(null);

  Future<void> logout() async {
    final cur = state;
    _set(null);
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
      .watch(casaApiProvider)
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
      .watch(casaApiProvider)
      .getCash(s.token, barbershopId: s.shopId, month: month);
});

final clientSearchProvider = FutureProvider.autoDispose
    .family<List<ClientFile>, String>((ref, q) {
      final s = _session(ref);
      return ref
          .watch(casaApiProvider)
          .searchClients(s.token, barbershopId: s.shopId, q: q);
    });

final clientDetailProvider = FutureProvider.autoDispose
    .family<ClientDetail, String>((ref, id) {
      final s = _session(ref);
      return ref
          .watch(casaApiProvider)
          .getClient(s.token, barbershopId: s.shopId, clientId: id);
    });

/// Lista de gestão (só gerente): inclui inativos.
final professionalsProvider = FutureProvider.autoDispose<List<Professional>>((
  ref,
) {
  final s = _session(ref);
  return ref
      .watch(casaApiProvider)
      .listProfessionals(s.token, barbershopId: s.shopId);
});

final activeServicesProvider = FutureProvider.autoDispose<List<Service>>((ref) {
  final s = _session(ref);
  return ref.watch(casaApiProvider).activeServices(barbershopId: s.shopId);
});

String monthKey(SpDate d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
