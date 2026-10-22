import 'dart:io';

import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/core/phone/phone.dart';
import 'package:flutter_test/flutter_test.dart';

/// Confere o app contra `api/openapi.yaml` (só lê o arquivo, não muda nada).
void main() {
  final yaml = File('../api/openapi.yaml').readAsLinesSync();

  test('os códigos de erro do app são os do contrato (ErrorCode)', () {
    final start = yaml.indexWhere((l) => l.trim() == 'ErrorCode:');
    expect(start, isNot(-1));
    final enumAt = yaml.indexWhere((l) => l.trim() == 'enum:', start);
    final codes = <String>[];
    for (var i = enumAt + 1; i < yaml.length; i++) {
      final m = RegExp(r'^\s+- ([A-Z_]+)\s*$').firstMatch(yaml[i]);
      if (m == null) break;
      codes.add(m.group(1)!);
    }
    expect(codes, contains('SLOT_IN_PAST'));
    expect(codes, contains('STATUS_CHANGED'));
    expect(codes, isNot(contains('INVALID_STATUS_TRANSITION')));
    expect(ErrorCode.values.map((c) => c.wire), codes);
  });

  test('o telefone normalizado segue o padrão de telefone do contrato', () {
    final patterns = yaml
        .map((l) => RegExp(r"phone: \{[^}]*pattern: '([^']+)'").firstMatch(l))
        .whereType<RegExpMatch>()
        .map((m) => m.group(1)!)
        .toSet();
    expect(patterns, {r'^\+55\d{10,11}$'});
    final re = RegExp(patterns.single);
    for (final entrada in [
      '(11) 98765-4321',
      '+55 11 98765-4321',
      '5511987654321',
      '(11) 3456-7890',
    ]) {
      expect(normalizePhone(entrada), matches(re), reason: entrada);
    }
  });

  test('ClientInfo.phone: texto de 10 a 20 caracteres, como no contrato', () {
    final i = yaml.indexWhere((l) => l.trim() == 'ClientInfo:');
    final block = yaml.skip(i).take(20).join('\n');
    expect(block, contains('minLength: $kPhoneInputMin'));
    expect(block, contains('maxLength: $kPhoneInputMax'));
  });
}
