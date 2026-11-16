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
    this.firstName,
    this.lastName,
    this.nickname,
    this.draftPhone,
    this.disconnectedNotice = false,
  });

  /// Já leu o que estava salvo.
  final bool hydrated;

  /// A introdução aparece na primeira abertura e de novo sempre que o app volta
  /// a ser novo: "Entrar como cliente novo" (só mock) e aparelho desconectado
  /// pela barbearia (401). Resposta 4 do PO no PR #7 da QA.
  final bool introSeen;

  /// Código do aparelho, preso a [boundPhone]. Nunca aparece na tela.
  final String? clientCode;

  /// Telefone (`+55...`) a que o código está preso.
  final String? boundPhone;

  /// Nome usado no agendamento: "Nome Sobrenome".
  final String? clientName;

  /// Nome, sobrenome e apelido cadastrados. O Início mostra só estes.
  final String? firstName;
  final String? lastName;
  final String? nickname;

  /// Telefone que a pessoa cadastrou, ainda sem agendamento aceito.
  /// Não trava o campo: o número mockado do João não entra aqui.
  final String? draftPhone;

  /// O aparelho acabou de ser desconectado pela barbearia (401 com o código
  /// salvo): o app mostra o aviso uma vez e chama
  /// [DeviceStore.ackDisconnectedNotice]. Só em memória.
  final bool disconnectedNotice;

  /// Aparelho preso a um telefone: tem horários para listar e cancelar.
  bool get hasSession => clientCode != null && boundPhone != null;

  /// Número para mostrar no Menu. O Início não usa.
  String? get phoneOnFile => hasSession ? boundPhone : draftPhone;

  /// "Nome Sobrenome" para o Início. Se ainda não separou, usa o nome antigo.
  String? get homeFullName {
    final joined = [
      firstName,
      lastName,
    ].map((s) => (s ?? '').trim()).where((s) => s.isNotEmpty).join(' ');
    if (joined.isNotEmpty) return joined;
    final legacy = (clientName ?? '').trim();
    return legacy.isEmpty ? null : legacy;
  }
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
  static const kFirstName = 'cortaaqui.cliente.first_name';
  static const kLastName = 'cortaaqui.cliente.last_name';
  static const kNickname = 'cortaaqui.cliente.nickname';
  static const kDraftPhone = 'cortaaqui.cliente.draft_phone';

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
        firstName: prefs.getString(kFirstName),
        lastName: prefs.getString(kLastName),
        nickname: prefs.getString(kNickname),
        draftPhone: complete ? null : prefs.getString(kDraftPhone),
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
      firstName: state.firstName,
      lastName: state.lastName,
      nickname: state.nickname,
      draftPhone: state.draftPhone,
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
      firstName: state.firstName,
      lastName: state.lastName,
      nickname: state.nickname,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kClientCode, code);
    await prefs.setString(kBoundPhone, phone);
    await prefs.setString(kClientName, name);
    await prefs.remove(kDraftPhone);
  }

  /// Cadastro do telefone, antes de qualquer agendamento. Não prende o
  /// aparelho: o campo continua editável e nenhum número mockado é usado.
  Future<void> savePhoneDraft({
    required String phone,
    required String firstName,
    required String lastName,
    required String nickname,
  }) async {
    final full = '$firstName $lastName'.trim();
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: state.introSeen,
      clientCode: state.clientCode,
      boundPhone: state.boundPhone,
      clientName: full,
      firstName: firstName,
      lastName: lastName,
      nickname: nickname,
      draftPhone: state.hasSession ? null : phone,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kClientName, full);
    await prefs.setString(kFirstName, firstName);
    await prefs.setString(kLastName, lastName);
    await prefs.setString(kNickname, nickname);
    if (!state.hasSession) {
      await prefs.setString(kDraftPhone, phone);
    }
  }

  /// Um pedido com o código salvo deu 401 (aparelho liberado pelo gerente na
  /// troca de celular): volta ao estado de cliente novo (sem código, telefone
  /// e nome, campo de telefone livre, introdução por ver). Com [notice], pede o
  /// aviso "Este aparelho foi desconectado pela barbearia." uma vez só: vários
  /// 401 seguidos (Início e Horários ao mesmo tempo) não repetem o aviso,
  /// porque depois do primeiro já não há sessão. Depois do aviso o `ClienteApp`
  /// abre a introdução. Sem [notice] (código preso a outro telefone, só por
  /// chamada direta) só solta o aparelho.
  Future<void> disconnectedByShop({bool notice = true}) async {
    if (state.clientCode == null && state.boundPhone == null) return;
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: notice ? false : state.introSeen,
      disconnectedNotice: notice,
    );
    await _removeClient();
    if (notice) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kIntroSeen);
    }
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
      firstName: state.firstName,
      lastName: state.lastName,
      nickname: state.nickname,
      draftPhone: state.draftPhone,
    );
  }

  Future<void> _removeClient() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kClientCode);
    await prefs.remove(kBoundPhone);
    await prefs.remove(kClientName);
    await prefs.remove(kFirstName);
    await prefs.remove(kLastName);
    await prefs.remove(kNickname);
    await prefs.remove(kDraftPhone);
  }

  /// "Entrar como cliente novo" (só no modo mock): esquece código, telefone e
  /// nome e a introdução volta a aparecer, como num aparelho limpo. A sessão do
  /// seed não volta na próxima abertura (a marca dela fica). O código apagado continua preso ao João no "servidor" do mock,
  /// como no servidor de verdade: só a liberação pelo gerente solta.
  Future<void> forgetClient() async {
    state = DeviceState(hydrated: state.hydrated);
    await _removeClient();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kIntroSeen);
  }
}

final deviceStoreProvider = NotifierProvider<DeviceStore, DeviceState>(
  DeviceStore.new,
);
