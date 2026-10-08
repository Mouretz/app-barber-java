import 'dart:math';

final Random _random = Random.secure();

/// UUID v4 (usado no `Idempotency-Key` e nos ids do mock).
String newUuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Código opaco do cliente (32 caracteres hex). Nunca aparece na tela.
String newClientCode() => List<int>.generate(
  16,
  (_) => _random.nextInt(256),
).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
