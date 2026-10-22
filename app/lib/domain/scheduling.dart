import 'package:flutter/foundation.dart';

import '../core/time/sao_paulo.dart';
import '../data/models/availability.dart';
import '../data/models/booking.dart';

/// Regras de agenda do MVP (respostas do PO Dev e plano da QA). Código puro, sem
/// Flutter nem repositório, para o mock usar hoje e os testes cobrirem os limites.
/// Quando o app ligar na API, quem calcula é o servidor; a tela só mostra.
abstract final class SchedulingRules {
  /// Os horários começam de 30 em 30 minutos, no relógio (08:00, 08:30...).
  static const int slotMinutes = 30;

  /// Antecedência mínima do cliente pelo app.
  static const Duration minLead = Duration(minutes: 30);

  /// A agenda abre 14 dias contando com hoje (hoje até hoje + 13).
  static const int horizonDays = 14;

  /// Máximo de horários futuros por telefone, marcados pelo app.
  static const int maxFutureClientBookings = 2;

  /// O cliente cancela até 2h antes (exatamente 2h ainda pode).
  static const Duration cancelWindow = Duration(hours: 2);
}

/// Janela de expediente em minutos do dia, `[start, end)`.
@immutable
class WorkWindow {
  const WorkWindow(this.startMinute, this.endMinute)
    : assert(endMinute > startMinute);

  /// `WorkWindow.hm('08:00', '12:00')`.
  factory WorkWindow.hm(String start, String end) =>
      WorkWindow(_parseHm(start), _parseHm(end));

  final int startMinute;
  final int endMinute;

  static int _parseHm(String hm) {
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is WorkWindow &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(startMinute, endMinute);
}

/// Intervalo de tempo `[start, end)` em instantes UTC.
@immutable
class TimeSpan {
  const TimeSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Encostado não bate: 10:00–10:30 e 10:30–11:00 não se sobrepõem.
  bool overlaps(TimeSpan o) => start.isBefore(o.end) && o.start.isBefore(end);
}

/// Dia dentro da janela de 14 dias (hoje até hoje + 13, em São Paulo)?
bool isWithinHorizon(SpDate date, DateTime now) {
  final today = SpDate.of(now);
  final diff = today.daysUntil(date);
  return diff >= 0 && diff < SchedulingRules.horizonDays;
}

/// Os 14 dias que o seletor da tela Agendar mostra.
List<SpDate> bookableDays(DateTime now) {
  final today = SpDate.of(now);
  return [
    for (var i = 0; i < SchedulingRules.horizonDays; i++) today.addDays(i),
  ];
}

/// Começa em :00 ou :30 cravado (sem segundos).
bool isOnGrid(DateTime start) {
  final w = spWall(start);
  return w.second == 0 &&
      w.millisecond == 0 &&
      w.microsecond == 0 &&
      w.minute % SchedulingRules.slotMinutes == 0;
}

/// Pelo menos 30 min de antecedência, contando segundos (09:30:00 para 10:00
/// pode; 09:30:01 não).
bool hasMinLead(DateTime start, DateTime now) =>
    !start.isBefore(now.add(SchedulingRules.minLead));

/// O serviço inteiro cabe numa janela de expediente do dia?
bool fitsWorkingHours(
  DateTime start,
  int durationMinutes,
  List<WorkWindow> windows,
) {
  final startMin = spMinuteOfDay(start);
  final endMin = startMin + durationMinutes;
  return windows.any((w) => startMin >= w.startMinute && endMin <= w.endMinute);
}

/// Bate com algo que ocupa a agenda?
bool overlapsBusy(DateTime start, int durationMinutes, List<TimeSpan> busy) {
  final span = TimeSpan(start, start.add(Duration(minutes: durationMinutes)));
  return busy.any(span.overlaps);
}

/// O que ocupa a agenda de um profissional: marcações agendadas ou concluídas
/// e bloqueios. Falta e cancelado não ocupam.
List<TimeSpan> busySpans({
  required Iterable<Booking> bookings,
  Iterable<TimeSpan> blocks = const [],
}) {
  return [
    for (final b in bookings)
      if (b.status.occupiesSlot) TimeSpan(b.startAt, b.endAt),
    ...blocks,
  ];
}

/// Horários livres de um profissional num dia para um serviço (regra do
/// cliente pelo app). Um horário só entra se:
/// - o dia está entre hoje e hoje + 13 (São Paulo);
/// - começa na grade de 30 min;
/// - o serviço inteiro cabe numa janela do expediente (combo de 60 min ocupa 2
///   horários seguidos dentro da mesma janela);
/// - não bate com marcação agendada/concluída nem com bloqueio;
/// - começa com pelo menos 30 min de antecedência.
List<AvailabilitySlot> computeFreeSlots({
  required SpDate date,
  required DateTime now,
  required int durationMinutes,
  required List<WorkWindow> windows,
  required List<TimeSpan> busy,
}) {
  if (!isWithinHorizon(date, now)) return const [];
  const step = SchedulingRules.slotMinutes;
  final starts = <int>{};
  for (final w in windows) {
    final first = ((w.startMinute + step - 1) ~/ step) * step;
    for (var m = first; m + durationMinutes <= w.endMinute; m += step) {
      starts.add(m);
    }
  }
  final sorted = starts.toList()..sort();
  final slots = <AvailabilitySlot>[];
  for (final m in sorted) {
    final start = date.at(m);
    if (!hasMinLead(start, now)) continue;
    if (overlapsBusy(start, durationMinutes, busy)) continue;
    slots.add(AvailabilitySlot(startAt: start, period: Period.ofMinute(m)));
  }
  return slots;
}

/// Cliente pode cancelar? Só `agendado` e até 2h antes do início.
bool clientCanCancel(Booking b, DateTime now) =>
    b.status == BookingStatus.scheduled &&
    !now.isAfter(b.startAt.subtract(SchedulingRules.cancelWindow));

/// Conta para o limite de 2: marcado pelo app, agendado e ainda no futuro.
bool countsForClientLimit(Booking b, DateTime now) =>
    b.source == BookingSource.clientApp &&
    b.status == BookingStatus.scheduled &&
    b.startAt.isAfter(now);
