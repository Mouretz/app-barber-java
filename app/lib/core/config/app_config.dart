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

  /// Valor desconhecido cai no mock: o APK de teste nunca tenta um servidor sem querer.
  static DataSource parseDataSource(String raw) {
    return raw.trim().toLowerCase() == 'api' ? DataSource.api : DataSource.mock;
  }
}
