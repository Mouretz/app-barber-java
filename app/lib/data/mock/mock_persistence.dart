import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Onde o mock guarda o estado entre aberturas do app (o checklist da QA pede
/// que os dados continuem depois de fechar à força).
abstract class MockPersistence {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> json);
}

/// Não guarda nada (testes).
class MemoryMockPersistence implements MockPersistence {
  Map<String, dynamic>? _data;

  @override
  Future<Map<String, dynamic>?> load() async => _data;

  @override
  Future<void> save(Map<String, dynamic> json) async => _data = json;
}

class PrefsMockPersistence implements MockPersistence {
  PrefsMockPersistence({this.key = kClienteKey});

  static const kClienteKey = 'cortaaqui.mock.cliente.state';

  /// O app Casa é outro APK: guarda o "servidor" dele em outra chave.
  static const kCasaKey = 'cortaaqui.mock.casa.state';

  final String key;

  @override
  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(json));
  }
}
