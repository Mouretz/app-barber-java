import 'package:equatable/equatable.dart';

import '../../core/time/sao_paulo.dart';

/// `Period` do contrato. Só filtro de tela, pelo início do horário.
enum Period {
  morning('MORNING', 'Manhã'),
  afternoon('AFTERNOON', 'Tarde'),
  evening('EVENING', 'Noite');

  const Period(this.wire, this.label);
  final String wire;
  final String label;

  static Period fromWire(String raw) =>
      Period.values.firstWhere((p) => p.wire == raw);

  /// Manhã antes de 12:00, tarde de 12:00 a 17:59, noite a partir de 18:00.
  static Period ofMinute(int minuteOfDay) {
    if (minuteOfDay < 12 * 60) return Period.morning;
    if (minuteOfDay < 18 * 60) return Period.afternoon;
    return Period.evening;
  }
}

class AvailabilitySlot extends Equatable {
  const AvailabilitySlot({required this.startAt, required this.period});

  factory AvailabilitySlot.fromJson(Map<String, dynamic> j) => AvailabilitySlot(
    startAt: parseInstant(j['startAt'] as String),
    period: Period.fromWire(j['period'] as String),
  );

  final DateTime startAt;
  final Period period;

  Map<String, dynamic> toJson() => {
    'startAt': toIsoSp(startAt),
    'period': period.wire,
  };

  @override
  List<Object?> get props => [startAt, period];
}

/// `Availability` do contrato.
class Availability extends Equatable {
  const Availability({
    required this.date,
    required this.professionalId,
    required this.serviceId,
    required this.slots,
  });

  factory Availability.fromJson(Map<String, dynamic> j) => Availability(
    date: SpDate.parse(j['date'] as String),
    professionalId: j['professionalId'] as String,
    serviceId: j['serviceId'] as String,
    slots: (j['slots'] as List)
        .map((e) => AvailabilitySlot.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final SpDate date;
  final String professionalId;
  final String serviceId;
  final List<AvailabilitySlot> slots;

  List<AvailabilitySlot> inPeriod(Period p) =>
      slots.where((s) => s.period == p).toList();

  Map<String, dynamic> toJson() => {
    'date': date.toIso(),
    'professionalId': professionalId,
    'serviceId': serviceId,
    'slots': slots.map((s) => s.toJson()).toList(),
  };

  @override
  List<Object?> get props => [date, professionalId, serviceId, slots];
}
