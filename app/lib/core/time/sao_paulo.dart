import 'package:flutter/foundation.dart';

/// Hora de Brasília (`America/Sao_Paulo`). Sem horário de verão desde 2019, então
/// o offset é fixo em -03:00. Se isso mudar, troque só este arquivo.
const Duration kSaoPauloOffset = Duration(hours: -3);

/// Dia do calendário em São Paulo, sem hora.
@immutable
class SpDate implements Comparable<SpDate> {
  const SpDate(this.year, this.month, this.day);

  /// Dia em São Paulo do instante [instant].
  factory SpDate.of(DateTime instant) {
    final w = spWall(instant);
    return SpDate(w.year, w.month, w.day);
  }

  /// `2026-10-08`.
  factory SpDate.parse(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return SpDate(p[0], p[1], p[2]);
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utcMidnight => DateTime.utc(year, month, day);

  /// 1 = segunda ... 7 = domingo.
  int get weekday => _utcMidnight.weekday;

  SpDate addDays(int days) {
    final d = DateTime.utc(year, month, day + days);
    return SpDate(d.year, d.month, d.day);
  }

  int daysUntil(SpDate other) =>
      other._utcMidnight.difference(_utcMidnight).inDays;

  /// Instante em que o relógio de São Paulo marca este dia + [minuteOfDay].
  DateTime at(int minuteOfDay) => _utcMidnight
      .add(Duration(minutes: minuteOfDay))
      .subtract(kSaoPauloOffset);

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}-${_two(day)}';

  @override
  int compareTo(SpDate other) => _utcMidnight.compareTo(other._utcMidnight);

  bool isBefore(SpDate other) => compareTo(other) < 0;
  bool isAfter(SpDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is SpDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// Campos de relógio de parede em São Paulo (o `DateTime` volta marcado como UTC,
/// mas ano/mês/dia/hora/minuto são os de Brasília). Só para exibir e calcular dia.
DateTime spWall(DateTime instant) => instant.toUtc().add(kSaoPauloOffset);

/// Minuto do dia em São Paulo (0 a 1439).
int spMinuteOfDay(DateTime instant) {
  final w = spWall(instant);
  return w.hour * 60 + w.minute;
}

/// ISO 8601 com o offset de Brasília, como o contrato pede:
/// `2026-10-08T14:30:00-03:00`.
String toIsoSp(DateTime instant) {
  final w = spWall(instant);
  return '${SpDate(w.year, w.month, w.day).toIso()}T'
      '${_two(w.hour)}:${_two(w.minute)}:${_two(w.second)}-03:00';
}

/// Lê data-hora ISO com offset e devolve o instante em UTC.
DateTime parseInstant(String iso) => DateTime.parse(iso).toUtc();

/// `HH:mm` em São Paulo.
String formatHm(DateTime instant) {
  final w = spWall(instant);
  return '${_two(w.hour)}:${_two(w.minute)}';
}

String _two(int v) => v.toString().padLeft(2, '0');
