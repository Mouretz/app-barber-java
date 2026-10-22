import 'package:flutter_test/flutter_test.dart';

import 'package:cortaaqui/core/config/app_config.dart';
import 'package:cortaaqui/core/config/build_mode.dart';

void main() {
  test('build padrão dos testes é mock', () {
    expect(kBuildIsMock, isTrue);
  });

  test('mock e api exatos batem com o const', () {
    expect(
      () => checkBuildMode(parsedIsMock: true, buildIsMock: true),
      returnsNormally,
    );
    expect(
      () => checkBuildMode(parsedIsMock: false, buildIsMock: false),
      returnsNormally,
    );
  });

  test(
    '" Mock " normaliza pra mock mas o const daria api: para na abertura',
    () {
      final parsed = AppConfig.parseDataSource(' Mock ');
      expect(parsed, DataSource.mock);
      expect(
        () => checkBuildMode(
          parsedIsMock: parsed == DataSource.mock,
          buildIsMock: ' Mock ' == 'mock',
        ),
        throwsArgumentError,
      );
    },
  );
}
