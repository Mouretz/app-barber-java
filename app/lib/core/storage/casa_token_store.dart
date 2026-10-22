import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Onde o token da Casa fica guardado. Nunca no SharedPreferences: no
/// aparelho vai para o armazenamento seguro (Keystore/Keychain).
abstract class CasaTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureCasaTokenStore implements CasaTokenStore {
  SecureCasaTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const kToken = 'cortaaqui.casa.token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: kToken);

  @override
  Future<void> write(String token) => _storage.write(key: kToken, value: token);

  @override
  Future<void> delete() => _storage.delete(key: kToken);
}

/// Para testes: guarda só em memória.
class MemoryCasaTokenStore implements CasaTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> delete() async => token = null;
}
