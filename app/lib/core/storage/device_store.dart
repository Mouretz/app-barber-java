import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O que fica guardado no aparelho do cliente.
class DeviceState {
  const DeviceState({
    this.hydrated = false,
    this.introSeen = false,
    this.clientCode,
  });

  /// Já leu o que estava salvo.
  final bool hydrated;

  /// A introdução aparece só na primeira abertura (pergunta 8 da QA em aberto).
  final bool introSeen;

  /// Código do cliente (`X-Client-Code`), guardado no primeiro agendamento.
  /// Nunca aparece na tela.
  final String? clientCode;

  DeviceState copyWith({bool? hydrated, bool? introSeen, String? clientCode}) {
    return DeviceState(
      hydrated: hydrated ?? this.hydrated,
      introSeen: introSeen ?? this.introSeen,
      clientCode: clientCode ?? this.clientCode,
    );
  }
}

class DeviceStore extends Notifier<DeviceState> {
  static const kIntroSeen = 'cortaaqui.cliente.intro_seen';
  static const kClientCode = 'cortaaqui.cliente.client_code';

  @override
  DeviceState build() {
    unawaited(_restore());
    return const DeviceState();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = DeviceState(
        hydrated: true,
        introSeen: prefs.getBool(kIntroSeen) ?? false,
        clientCode: prefs.getString(kClientCode),
      );
    } catch (_) {
      state = const DeviceState(hydrated: true);
    }
  }

  Future<void> markIntroSeen() async {
    state = state.copyWith(introSeen: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kIntroSeen, true);
  }

  Future<void> saveClientCode(String code) async {
    state = state.copyWith(clientCode: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kClientCode, code);
  }
}

final deviceStoreProvider = NotifierProvider<DeviceStore, DeviceState>(
  DeviceStore.new,
);
