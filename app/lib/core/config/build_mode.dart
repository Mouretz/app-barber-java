/// `true` quando o build foi feito com `DATA_SOURCE=mock` (padrão).
///
/// É `const`: no build `api` o compilador corta todo ramo `if (kBuildIsMock)`,
/// e o código do mock (seed, senha de teste, repositórios) não entra no
/// APK nem no `main.dart.js`.
///
/// Dart não tem `trim()`/`toLowerCase()` em `const`, então aqui a comparação
/// é exata. Para não divergir de `AppConfig.parseDataSource` (que aceita
/// espaço e maiúscula), `AppConfig.fromEnvironment` chama
/// `checkBuildMode`: um `DATA_SOURCE=" Mock "` para o app na abertura em vez
/// de rodar meio mock, meio api.
const bool kBuildIsMock =
    String.fromEnvironment('DATA_SOURCE', defaultValue: 'mock') == 'mock';

/// Falha se o `DATA_SOURCE` normalizado diz `mock` mas o `const` não (ou o
/// contrário). Recebe os valores por parâmetro para dar pra testar.
void checkBuildMode({required bool parsedIsMock, required bool buildIsMock}) {
  if (parsedIsMock != buildIsMock) {
    throw ArgumentError(
      'DATA_SOURCE precisa ser exatamente "mock" ou "api" (minúsculo, sem '
      'espaço) no --dart-define',
    );
  }
}
