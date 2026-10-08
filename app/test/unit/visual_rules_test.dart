import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CT-09-11: o cinza #636366 saiu (reprova no contraste). O tema já tem o
/// teste dele; este confere que nenhuma tela do app usa esse cinza solto.
void main() {
  test('nenhum arquivo de lib/ usa o cinza 636366', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync().toUpperCase();
      if (src.contains('636366')) hits.add(f.path);
    }
    expect(hits, isEmpty);
  });
}
