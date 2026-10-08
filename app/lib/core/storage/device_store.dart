import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O que fica guardado no aparelho do cliente.
///
/// O código do aparelho (`X-Client-Code`) nasce no app, mas só é guardado
/// quando o primeiro agendamento é aceito. Junto fica o telefone a que ele foi
/// preso, e o campo de telefone passa a vir travado com esse número. Recusa no
/// primeiro agendamento (limite, antecedência, 14 dias, horário ocupado,
/// telefone em outro aparelho...) não guarda nada (regra do PO, 07/10).
class DeviceState {
  const DeviceState({
    this.hydrated = false,
    this.introSeen = false,
    this.clientCode,
    this.boundPhone,
    this.clientName,
    this.disconnectedNotice = false,
  });

  /// Já leu o que estava salvo.
  final bool hydrated;

  /// A introdução aparece só na primeira abertura (pergunta 4 da QA em aberto).
  final bool introSeen;

  /// Código do aparelho, preso a [boundPhone]. Nunca aparece na tela.
  final String? clientCode;

  /// Telefone (`+55...`) a que o código está preso.
  final String? boundPhone;

  /// Nome usado no último agendamento aceito (só para preencher o campo).
  final String? clientName;

  /// O aparelho acabou de ser desconectado pela barbearia (401 com o código
  /// salvo): o app mostra o aviso uma vez e chama
  /// [DeviceStore.ackDisconnectedNotice]. Só em memória.
  final bool disconnectedNotice;

  /// Aparelho preso a um telefone: tem horários para listar e cancelar.
  bool get hasSession => clientCode != null && boundPhone != null;
}

/// Sessão que o aparelho já traz na primeira abertura, como se o cliente
/// tivesse agendado por ele antes. Só o modo mock tem (o João do seed, plano da
/// QA, seção 2); no modo api o provider fica `null` e nada muda.
class SeedSession {
  const SeedSession({
    required this.code,
    required this.phone,
    required this.name,
  });

  final String code;
  final String phone;
  final String name;
}

/// `null` por padrão. `runCortaAqui` sobrescreve só no modo mock.
final seedSessionProvider = Provider<SeedSession?>((ref) => null);

class DeviceStore extends Notifier<DeviceState> {
  static const kIntroSeen = 'cortaaqui.cliente.intro_seen';
  static const kClientCode = 'cortaaqui.cliente.client_code';
  static const kBoundPhone = 'cortaaqui.cliente.bound_phone';
  static const kClientName = 'cortaaqui.cliente.client_name';

  /// A sessão do seed (modo mock) já foi posta neste aparelho. Fica gravado
  /// para "Entrar como cliente novo" não ser desfeito na próxima abertura.
  static const kSeedSessionApplied = 'cortaaqui.cliente.seed_session_applied';

  @override
  DeviceState build() {
    unawaited(_restore());
    return const DeviceState();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _applySeedSession(prefs);
      final code = prefs.getString(kClientCode);
      final phone = prefs.getString(kBoundPhone);
      final complete = code != null && phone != null;
      state = DeviceState(
        hydrated: true,
        introSeen: prefs.getBool(kIntroSeen) ?? false,
        clientCode: complete ? code : null,
        boundPhone: complete ? phone : null,
        clientName: prefs.getString(kClientName),
      );
    } catch (_) {
      state = const DeviceState(hydrated: true);
    }
  }

  /// Primeira abertura no modo mock: o aparelho já vem preso ao cliente do
  /// seed. Só uma vez por instalação; um aparelho que já tem código fica como
  /// está.
  Future<void> _applySeedSession(SharedPreferences prefs) async {
    final seed = ref.read(seedSessionProvider);
    if (seed == null || (prefs.getBool(kSeedSessionApplied) ?? false)) return;
    if (prefs.getString(kClientCode) == null) {
      await prefs.setString(kClientCode, seed.code);
      await prefs.setString(kBoundPhone, seed.phone);
      await prefs.setString(kClientName, seed.name);
    }
    await prefs.setBool(kSeedSessionApplied, true);
  }

  Future<void> markIntroSeen() async {
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: true,
      clientCode: state.clientCode,
      boundPhone: state.boundPhone,
      clientName: state.clientName,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kIntroSeen, true);
  }

  /// Chamado só depois de o agendamento ser aceito.
  Future<void> bindAfterAcceptedBooking({
    required String code,
    required String phone,
    required String name,
  }) async {
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: state.introSeen,
      clientCode: code,
      boundPhone: phone,
      clientName: name,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kClientCode, code);
    await prefs.setString(kBoundPhone, phone);
    await prefs.setString(kClientName, name);
  }

  /// Um pedido com o código salvo deu 401 (aparelho liberado pelo gerente na
  /// troca de celular): volta ao estado de cliente novo (sem código, telefone
  /// e nome, campo de telefone livre). Com [notice], pede o aviso "Este
  /// aparelho foi desconectado pela barbearia." uma vez só: vários 401 seguidos
  /// (Início e Horários ao mesmo tempo) não repetem o aviso, porque depois do
  /// primeiro já não há sessão.
  Future<void> disconnectedByShop({bool notice = true}) async {
    if (state.clientCode == null && state.boundPhone == null) return;
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: state.introSeen,
      disconnectedNotice: notice,
    );
    await _removeClient();
  }

  /// O aviso de desconexão já foi mostrado.
  void ackDisconnectedNotice() {
    if (!state.disconnectedNotice) return;
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: state.introSeen,
      clientCode: state.clientCode,
      boundPhone: state.boundPhone,
      clientName: state.clientName,
    );
  }

  Future<void> _removeClient() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kClientCode);
    await prefs.remove(kBoundPhone);
    await prefs.remove(kClientName);
  }

  /// "Entrar como cliente novo" (só no modo mock): esquece código, telefone e
  /// nome, como um aparelho limpo. A introdução continua vista (ela é da
  /// instalação, não do cliente), e a sessão do seed não volta na próxima
  /// abertura. O código apagado continua preso ao João no "servidor" do mock,
  /// como no servidor de verdade: só a liberação pelo gerente solta.
  Future<void> forgetClient() async {
    state = DeviceState(hydrated: state.hydrated, introSeen: state.introSeen);
    await _removeClient();
  }
}

final deviceStoreProvider = NotifierProvider<DeviceStore, DeviceState>(
  DeviceStore.new,
);
