/// `true` quando o build foi feito com `DATA_SOURCE=mock` (padrão).
///
/// É `const`: no build `api` o compilador corta todo ramo `if (kBuildIsMock)`,
/// e o código do mock (seed, senha de teste, repositórios) não entra no
/// APK nem no `main.dart.js`.
const bool kBuildIsMock =
    String.fromEnvironment('DATA_SOURCE', defaultValue: 'mock') == 'mock';
