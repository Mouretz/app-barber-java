/// Relógio injetável. Sempre devolve o instante em UTC; a conversão para a hora
/// de Brasília fica em `sao_paulo.dart`. Nos testes entra um [FixedClock].
abstract class Clock {
  const Clock();

  DateTime now();
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Relógio parado, para teste. Dá para avançar com [advance] ou trocar com [set].
class FixedClock extends Clock {
  FixedClock(DateTime now) : _now = now.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void set(DateTime now) => _now = now.toUtc();

  void advance(Duration d) => _now = _now.add(d);
}
