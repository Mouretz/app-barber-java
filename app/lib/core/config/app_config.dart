/// Qual dos dois apps está rodando. Vem do ponto de entrada
/// (`main_cliente.dart` ou `main_casa.dart`), que casa com o flavor do Android.
enum Flavor {
  cliente('CortaAqui'),
  casa('CortaAqui Casa');

  const Flavor(this.appName);
  final String appName;
}

/// De onde vêm os dados. `mock` roda sem servidor (primeira entrega do APK).
enum DataSource { mock, api }

/// Configuração lida das `--dart-define` no build.
///
/// - `DATA_SOURCE`: `mock` (padrão) ou `api`.
/// - `API_BASE_URL`: base do servidor, usada só com `api`.
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.dataSource,
    required this.apiBaseUrl,
  });

  factory AppConfig.fromEnvironment(Flavor flavor) {
    return AppConfig(
      flavor: flavor,
      dataSource: parseDataSource(
        const String.fromEnvironment('DATA_SOURCE', defaultValue: 'mock'),
      ),
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://10.0.2.2:8080/api/v1',
      ),
    );
  }

  final Flavor flavor;
  final DataSource dataSource;
  final String apiBaseUrl;

  bool get isMock => dataSource == DataSource.mock;

  /// Só aceita `mock` ou `api`. Qualquer outro valor (inclusive vazio) é build mal
  /// configurado e o app para na abertura, em vez de virar mock em silêncio e mostrar
  /// o "Entrar como cliente novo" num APK que deveria falar com o servidor.
  static DataSource parseDataSource(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'mock':
        return DataSource.mock;
      case 'api':
        return DataSource.api;
      default:
        throw ArgumentError.value(
          raw,
          'DATA_SOURCE',
          'use mock ou api no --dart-define',
        );
    }
  }
}
