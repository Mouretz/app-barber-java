import 'package:equatable/equatable.dart';

import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import 'barbershop.dart';
import 'booking.dart';

/// `Role` do contrato. O papel é por barbearia (vem no `Membership`).
enum StaffRole {
  manager('MANAGER'),
  professional('PROFESSIONAL');

  const StaffRole(this.wire);
  final String wire;

  static StaffRole fromWire(String raw) =>
      StaffRole.values.firstWhere((r) => r.wire == raw);
}

/// `Membership`: vínculo da pessoa com uma barbearia.
class Membership extends Equatable {
  const Membership({
    required this.barbershopId,
    required this.barbershopName,
    required this.roles,
    this.professionalId,
  });

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
    barbershopId: j['barbershopId'] as String,
    barbershopName: j['barbershopName'] as String,
    roles: (j['roles'] as List)
        .map((e) => StaffRole.fromWire(e as String))
        .toSet(),
    professionalId: j['professionalId'] as String?,
  );

  final String barbershopId;
  final String barbershopName;
  final Set<StaffRole> roles;

  /// Preenchido só quando a pessoa atende aqui. Gerente que não atende (ou que
  /// foi desativado como profissional) vem com `null`: nunca é "minha agenda".
  final String? professionalId;

  bool get isManager => roles.contains(StaffRole.manager);

  /// Tem agenda própria nesta barbearia.
  bool get attends =>
      roles.contains(StaffRole.professional) && professionalId != null;

  Map<String, dynamic> toJson() => {
    'barbershopId': barbershopId,
    'barbershopName': barbershopName,
    'roles': roles.map((r) => r.wire).toList(),
    'professionalId': professionalId,
  };

  @override
  List<Object?> get props => [
    barbershopId,
    barbershopName,
    roles,
    professionalId,
  ];
}

/// `StaffUser` (`GET /auth/me`).
class StaffUser extends Equatable {
  const StaffUser({
    required this.id,
    required this.name,
    required this.email,
    required this.memberships,
  });

  final String id;
  final String name;
  final String email;
  final List<Membership> memberships;

  Membership? membershipAt(String barbershopId) =>
      memberships.where((m) => m.barbershopId == barbershopId).firstOrNull;

  @override
  List<Object?> get props => [id, name, email, memberships];
}

/// `Session` (`POST /auth/login`).
class StaffSession extends Equatable {
  const StaffSession({
    required this.accessToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final DateTime expiresAt;
  final StaffUser user;

  @override
  List<Object?> get props => [accessToken, expiresAt, user];
}

/// `Professional` (lista de gestão, só gerente). Inclui inativos.
class Professional extends Equatable {
  const Professional({
    required this.id,
    required this.name,
    required this.active,
    this.email,
  });

  final String id;
  final String name;
  final bool active;
  final String? email;

  ProfessionalPublic get public => ProfessionalPublic(id: id, name: name);

  Professional copyWith({String? name, bool? active}) => Professional(
    id: id,
    name: name ?? this.name,
    active: active ?? this.active,
    email: email,
  );

  @override
  List<Object?> get props => [id, name, active, email];
}

/// `Block` do contrato.
class Block extends Equatable {
  const Block({
    required this.id,
    required this.professionalId,
    required this.startAt,
    required this.endAt,
    this.reason,
  });

  final String id;
  final String professionalId;
  final DateTime startAt;
  final DateTime endAt;
  final String? reason;

  TimeSpan get span => TimeSpan(startAt, endAt);

  @override
  List<Object?> get props => [id, professionalId, startAt, endAt, reason];
}

/// `TimeOff` do contrato (folga com início e fim).
class TimeOff extends Equatable {
  const TimeOff({
    required this.id,
    required this.professionalId,
    required this.startAt,
    required this.endAt,
    this.reason,
  });

  final String id;
  final String professionalId;
  final DateTime startAt;
  final DateTime endAt;
  final String? reason;

  TimeSpan get span => TimeSpan(startAt, endAt);

  @override
  List<Object?> get props => [id, professionalId, startAt, endAt, reason];
}

/// Uma linha da `Agenda`: um profissional no dia.
class AgendaProfessional extends Equatable {
  const AgendaProfessional({
    required this.professional,
    required this.workingWindows,
    required this.bookings,
    required this.blocks,
    required this.timeOff,
  });

  final ProfessionalPublic professional;
  final List<WorkWindow> workingWindows;
  final List<Booking> bookings;
  final List<Block> blocks;
  final List<TimeOff> timeOff;

  @override
  List<Object?> get props => [
    professional,
    workingWindows,
    bookings,
    blocks,
    timeOff,
  ];
}

/// `Agenda` (`GET /barbershops/{id}/agenda`). Só profissionais ativos.
class Agenda extends Equatable {
  const Agenda({required this.date, required this.professionals});

  final SpDate date;
  final List<AgendaProfessional> professionals;

  @override
  List<Object?> get props => [date, professionals];
}

/// `StaffBookingRequest`. Use [clientId] OU [newClient].
class StaffBookingRequest extends Equatable {
  const StaffBookingRequest({
    required this.serviceId,
    required this.professionalId,
    required this.startAt,
    required this.source,
    this.clientId,
    this.newClientName,
    this.newClientPhone,
    this.note,
  });

  final String serviceId;
  final String professionalId;
  final DateTime startAt;

  /// `STAFF` (telefone obrigatório) ou `COUNTER` (balcão, telefone opcional).
  final BookingSource source;
  final String? clientId;
  final String? newClientName;
  final String? newClientPhone;
  final String? note;

  @override
  List<Object?> get props => [
    serviceId,
    professionalId,
    startAt,
    source,
    clientId,
    newClientName,
    newClientPhone,
    note,
  ];
}

/// `Client` (ficha desta barbearia).
class ClientFile extends Equatable {
  const ClientFile({
    required this.id,
    required this.name,
    required this.phone,
    required this.hasDevice,
    required this.createdAt,
    this.email,
  });

  final String id;
  final String name;

  /// `null` na ficha de balcão sem telefone.
  final String? phone;
  final bool hasDevice;
  final String? email;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, name, phone, hasDevice, email, createdAt];
}

/// `ClientDetail`: ficha com os últimos agendamentos desta barbearia.
class ClientDetail extends Equatable {
  const ClientDetail({required this.client, required this.recentBookings});

  final ClientFile client;
  final List<Booking> recentBookings;

  @override
  List<Object?> get props => [client, recentBookings];
}

/// `CashTotals`. [shopCents] é `null` (campo ausente) para o profissional que
/// não é gerente.
class CashTotals extends Equatable {
  const CashTotals({
    required this.completedCount,
    required this.grossCents,
    required this.professionalCents,
    this.shopCents,
  });

  static const zero = CashTotals(
    completedCount: 0,
    grossCents: 0,
    professionalCents: 0,
    shopCents: 0,
  );

  final int completedCount;
  final int grossCents;
  final int professionalCents;
  final int? shopCents;

  CashTotals plus(Booking b) => CashTotals(
    completedCount: completedCount + 1,
    grossCents: grossCents + b.priceCents,
    professionalCents:
        professionalCents +
        professionalShare(b.priceCents, b.professionalPercent ?? 0),
    shopCents:
        (shopCents ?? 0) +
        b.priceCents -
        professionalShare(b.priceCents, b.professionalPercent ?? 0),
  );

  /// Sem a parte da casa (o que o profissional não gerente recebe).
  CashTotals get withoutShop => CashTotals(
    completedCount: completedCount,
    grossCents: grossCents,
    professionalCents: professionalCents,
  );

  Map<String, dynamic> toJson() => {
    'completedCount': completedCount,
    'grossCents': grossCents,
    if (shopCents != null) 'shopCents': shopCents,
    'professionalCents': professionalCents,
  };

  @override
  List<Object?> get props => [
    completedCount,
    grossCents,
    professionalCents,
    shopCents,
  ];
}

/// Valor do profissional num agendamento: preço × % arredondado pro centavo
/// mais próximo, meio centavo pra cima (HALF_UP), só com inteiros.
int professionalShare(int priceCents, int percent) =>
    (priceCents * percent + 50) ~/ 100;

class CashRow extends Equatable {
  const CashRow({required this.professional, required this.totals});

  final ProfessionalPublic professional;
  final CashTotals totals;

  @override
  List<Object?> get props => [professional, totals];
}

/// `MonthlyCash` (`GET /cash`).
class MonthlyCash extends Equatable {
  const MonthlyCash({
    required this.month,
    required this.totals,
    required this.byProfessional,
  });

  final String month;
  final CashTotals totals;
  final List<CashRow> byProfessional;

  @override
  List<Object?> get props => [month, totals, byProfessional];
}

/// `ProfessionalCash` (`GET /cash/professionals/{id}`).
class ProfessionalCash extends Equatable {
  const ProfessionalCash({
    required this.month,
    required this.professional,
    required this.totals,
    required this.bookings,
  });

  final String month;
  final ProfessionalPublic professional;
  final CashTotals totals;
  final List<Booking> bookings;

  @override
  List<Object?> get props => [month, professional, totals, bookings];
}

class CommissionSplit extends Equatable {
  const CommissionSplit({
    required this.shopPercent,
    required this.professionalPercent,
  });

  static const standard = CommissionSplit(
    shopPercent: 40,
    professionalPercent: 60,
  );

  final int shopPercent;
  final int professionalPercent;

  @override
  List<Object?> get props => [shopPercent, professionalPercent];
}

/// `CommissionSettings`: padrão da casa + quem tem % própria.
class CommissionSettings extends Equatable {
  const CommissionSettings({
    required this.standard,
    required this.professionals,
  });

  final CommissionSplit standard;
  final Map<String, CommissionSplit> professionals;

  CommissionSplit splitFor(String professionalId) =>
      professionals[professionalId] ?? standard;

  @override
  List<Object?> get props => [standard, professionals];
}

/// Serviço da casa com o que o gerente muda (`ServicePatch`).
class ServicePatch {
  const ServicePatch({
    this.name,
    this.durationMinutes,
    this.priceCents,
    this.active,
  });

  final String? name;
  final int? durationMinutes;
  final int? priceCents;
  final bool? active;
}
