import 'package:cortaaqui/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sem DATA_SOURCE o build é mock', () {
    final c = AppConfig.fromEnvironment(Flavor.cliente);
    expect(c.isMock, isTrue);
  });

  test('só "api" liga o servidor; o resto cai no mock', () {
    expect(AppConfig.parseDataSource('api'), DataSource.api);
    expect(AppConfig.parseDataSource(' API '), DataSource.api);
    expect(AppConfig.parseDataSource('mock'), DataSource.mock);
    expect(AppConfig.parseDataSource(''), DataSource.mock);
    expect(AppConfig.parseDataSource('prod'), DataSource.mock);
  });

  test('nomes dos apps', () {
    expect(Flavor.cliente.appName, 'CortaAqui');
    expect(Flavor.casa.appName, 'CortaAqui Casa');
  });
}
