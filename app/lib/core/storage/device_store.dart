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

  /// Aparelho preso a um telefone: tem horários para listar e cancelar.
  bool get hasSession => clientCode != null && boundPhone != null;
}

class DeviceStore extends Notifier<DeviceState> {
  static const kIntroSeen = 'cortaaqui.cliente.intro_seen';
  static const kClientCode = 'cortaaqui.cliente.client_code';
  static const kBoundPhone = 'cortaaqui.cliente.bound_phone';
  static const kClientName = 'cortaaqui.cliente.client_name';

  @override
  DeviceState build() {
    unawaited(_restore());
    return const DeviceState();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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

  /// Código revogado (troca de celular liberada pelo gerente) ou recusado pelo
  /// servidor: o aparelho volta ao estado sem código e destrava o telefone.
  Future<void> clearSession() async {
    if (state.clientCode == null && state.boundPhone == null) return;
    state = DeviceState(
      hydrated: state.hydrated,
      introSeen: state.introSeen,
      clientName: state.clientName,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kClientCode);
    await prefs.remove(kBoundPhone);
  }
}

final deviceStoreProvider = NotifierProvider<DeviceStore, DeviceState>(
  DeviceStore.new,
);
