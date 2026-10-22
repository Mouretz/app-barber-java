import 'mock_casa_state.dart';

/// Dica dos logins de teste na tela de entrar. Só é importada pelo mock.
class MockLoginHint {
  const MockLoginHint({required this.logins, required this.password});

  final List<(String, String)> logins;
  final String password;

  static const casa = MockLoginHint(
    logins: [
      ('Gerente (não atende)', MockCasaSeed.marinaEmail),
      ('Gerente e profissional', MockCasaSeed.caioEmail),
      ('Profissional', MockCasaSeed.helenaEmail),
    ],
    password: MockCasaSeed.mockPassword,
  );
}
