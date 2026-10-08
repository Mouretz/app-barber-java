import 'package:cortaaqui/core/phone/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CT-17-11 normalização do telefone', () {
    const iguais = {
      '(11) 98765-4321': '+5511987654321',
      '11987654321': '+5511987654321',
      '+55 11 98765-4321': '+5511987654321',
      '+5511987654321': '+5511987654321',
      '5511987654321': '+5511987654321',
      '55 (11) 98765-4321': '+5511987654321',
      ' 11 98765 4321 ': '+5511987654321',
      '11.98765.4321': '+5511987654321',
      '(11) 3456-7890': '+551134567890',
      '551134567890': '+551134567890',
      '+55 (21) 91234-5678': '+5521912345678',
    };
    iguais.forEach((entrada, esperado) {
      test('"$entrada" -> $esperado', () {
        expect(normalizePhone(entrada), esperado);
      });
    });

    test('as 4 formas de T1 viram o mesmo número', () {
      final set = {
        normalizePhone('(11) 98765-4321'),
        normalizePhone('11987654321'),
        normalizePhone('+55 11 98765-4321'),
        normalizePhone('5511987654321'),
      };
      expect(set, {'+5511987654321'});
    });
  });

  group('CT-17-12 telefones recusados', () {
    const invalidos = [
      '987654321', // 9 dígitos
      '119876543210', // 12 dígitos sem 55
      '11 9876-ABCD', // letras
      '+1 212 555 0100', // DDI diferente de 55
      '+351 912 345 678', // DDI diferente de 55
      '', // vazio
      '+55 987654321', // 9 dígitos depois do 55
      '(01) 98765-4321', // DDD começando com 0
    ];
    for (final entrada in invalidos) {
      test('"$entrada" é recusado', () {
        expect(normalizePhone(entrada), isNull);
      });
    }
  });

  test(
    'o formato guardado é sempre +55 + DDD + número (padrão do contrato)',
    () {
      final pattern = RegExp(r'^\+55\d{10,11}$');
      for (final entrada in [
        '(11) 98765-4321',
        '1134567890',
        '5511987654321',
      ]) {
        expect(normalizePhone(entrada), matches(pattern), reason: entrada);
      }
    },
  );

  test('formata para mostrar', () {
    expect(formatPhone('+5511987654321'), '(11) 98765-4321');
    expect(formatPhone('+551134567890'), '(11) 3456-7890');
    expect(nationalDigits('+5511987654321'), '11987654321');
  });
}
