import 'package:cortaaqui/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sem DATA_SOURCE o build é mock', () {
    final c = AppConfig.fromEnvironment(Flavor.cliente);
    expect(c.isMock, isTrue);
  });

  test('aceita só mock e api', () {
    expect(AppConfig.parseDataSource('api'), DataSource.api);
    expect(AppConfig.parseDataSource(' API '), DataSource.api);
    expect(AppConfig.parseDataSource('mock'), DataSource.mock);
    expect(AppConfig.parseDataSource('Mock'), DataSource.mock);
  });

  test('valor desconhecido ou vazio para o app, nunca vira mock', () {
    for (final raw in ['', '  ', 'prod', 'apii', 'servidor']) {
      expect(
        () => AppConfig.parseDataSource(raw),
        throwsArgumentError,
        reason: 'DATA_SOURCE="$raw"',
      );
    }
  });

  test('nomes dos apps', () {
    expect(Flavor.cliente.appName, 'CortaAqui');
    expect(Flavor.casa.appName, 'CortaAqui Casa');
  });
}
