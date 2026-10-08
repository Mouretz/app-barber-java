import 'package:equatable/equatable.dart';

import '../../core/time/sao_paulo.dart';
import 'barbershop.dart';

enum BookingStatus {
  scheduled('SCHEDULED'),
  completed('COMPLETED'),
  noShow('NO_SHOW'),
  canceled('CANCELED');

  const BookingStatus(this.wire);
  final String wire;

  static BookingStatus fromWire(String raw) =>
      BookingStatus.values.firstWhere((s) => s.wire == raw);

  /// Ocupa a agenda (a trava): agendado e concluído. Falta e cancelado liberam.
  bool get occupiesSlot =>
      this == BookingStatus.scheduled || this == BookingStatus.completed;
}

enum BookingSource {
  clientApp('CLIENT_APP'),
  staff('STAFF'),
  counter('COUNTER');

  const BookingSource(this.wire);
  final String wire;

  static BookingSource fromWire(String raw) =>
      BookingSource.values.firstWhere((s) => s.wire == raw);
}

enum CanceledBy {
  client('CLIENT'),
  staff('STAFF');

  const CanceledBy(this.wire);
  final String wire;

  static CanceledBy? fromWire(String? raw) =>
      raw == null ? null : CanceledBy.values.firstWhere((s) => s.wire == raw);
}

class BookingServiceRef extends Equatable {
  const BookingServiceRef({required this.id, required this.name});

  factory BookingServiceRef.fromJson(Map<String, dynamic> j) =>
      BookingServiceRef(id: j['id'] as String, name: j['name'] as String);

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

class BookingClientRef extends Equatable {
  const BookingClientRef({required this.id, required this.name, this.phone});

  factory BookingClientRef.fromJson(Map<String, dynamic> j) => BookingClientRef(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String?,
  );

  final String id;
  final String name;

  /// Só a casa vê. Sempre no formato `+5511987654321`.
  final String? phone;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (phone != null) 'phone': phone,
  };

  @override
  List<Object?> get props => [id, name, phone];
}

/// `Booking` do contrato. Datas guardadas como instante UTC; vão e voltam em ISO
/// com o offset de Brasília.
class Booking extends Equatable {
  const Booking({
    required this.id,
    required this.barbershopId,
    this.barbershopName,
    required this.status,
    required this.source,
    required this.startAt,
    required this.endAt,
    required this.service,
    required this.professional,
    required this.client,
    required this.priceCents,
    this.shopPercent,
    this.professionalPercent,
    this.canCancel,
    this.canceledBy,
    this.note,
    required this.createdAt,
  });

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
    id: j['id'] as String,
    barbershopId: j['barbershopId'] as String,
    barbershopName: j['barbershopName'] as String?,
    status: BookingStatus.fromWire(j['status'] as String),
    source: BookingSource.fromWire(j['source'] as String),
    startAt: parseInstant(j['startAt'] as String),
    endAt: parseInstant(j['endAt'] as String),
    service: BookingServiceRef.fromJson(j['service'] as Map<String, dynamic>),
    professional: ProfessionalPublic.fromJson(
      j['professional'] as Map<String, dynamic>,
    ),
    client: BookingClientRef.fromJson(j['client'] as Map<String, dynamic>),
    priceCents: j['priceCents'] as int,
    shopPercent: j['shopPercent'] as int?,
    professionalPercent: j['professionalPercent'] as int?,
    canCancel: j['canCancel'] as bool?,
    canceledBy: CanceledBy.fromWire(j['canceledBy'] as String?),
    note: j['note'] as String?,
    createdAt: parseInstant(j['createdAt'] as String),
  );

  final String id;
  final String barbershopId;
  final String? barbershopName;
  final BookingStatus status;
  final BookingSource source;
  final DateTime startAt;
  final DateTime endAt;
  final BookingServiceRef service;
  final ProfessionalPublic professional;
  final BookingClientRef client;
  final int priceCents;
  final int? shopPercent;
  final int? professionalPercent;
  final bool? canCancel;
  final CanceledBy? canceledBy;
  final String? note;
  final DateTime createdAt;

  bool get canceledByShop =>
      status == BookingStatus.canceled && canceledBy == CanceledBy.staff;

  Booking copyWith({
    BookingStatus? status,
    bool? canCancel,
    CanceledBy? canceledBy,
    BookingClientRef? client,
    String? note,
  }) {
    return Booking(
      id: id,
      barbershopId: barbershopId,
      barbershopName: barbershopName,
      status: status ?? this.status,
      source: source,
      startAt: startAt,
      endAt: endAt,
      service: service,
      professional: professional,
      client: client ?? this.client,
      priceCents: priceCents,
      shopPercent: shopPercent,
      professionalPercent: professionalPercent,
      canCancel: canCancel ?? this.canCancel,
      canceledBy: canceledBy ?? this.canceledBy,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'barbershopId': barbershopId,
    if (barbershopName != null) 'barbershopName': barbershopName,
    'status': status.wire,
    'source': source.wire,
    'startAt': toIsoSp(startAt),
    'endAt': toIsoSp(endAt),
    'service': service.toJson(),
    'professional': professional.toJson(),
    'client': client.toJson(),
    'priceCents': priceCents,
    'shopPercent': shopPercent,
    'professionalPercent': professionalPercent,
    if (canCancel != null) 'canCancel': canCancel,
    'canceledBy': canceledBy?.wire,
    'note': note,
    'createdAt': toIsoSp(createdAt),
  };

  @override
  List<Object?> get props => [
    id,
    barbershopId,
    barbershopName,
    status,
    source,
    startAt,
    endAt,
    service,
    professional,
    client,
    priceCents,
    shopPercent,
    professionalPercent,
    canCancel,
    canceledBy,
    note,
    createdAt,
  ];
}

/// `ClientInfo` do contrato. [phone] vai do jeito que a pessoa digitou (com
/// máscara, com ou sem 55); quem normaliza para `+55...` é o servidor (ou o mock).
class ClientInfo extends Equatable {
  const ClientInfo({required this.name, required this.phone, this.email});

  final String name;
  final String phone;
  final String? email;

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    if (email != null) 'email': email,
  };

  @override
  List<Object?> get props => [name, phone, email];
}

/// `ClientBookingRequest` do contrato.
class ClientBookingRequest extends Equatable {
  const ClientBookingRequest({
    required this.serviceId,
    required this.professionalId,
    required this.startAt,
    this.client,
  });

  final String serviceId;
  final String professionalId;
  final DateTime startAt;

  /// Obrigatório sem código do cliente; ignorado com ele.
  final ClientInfo? client;

  Map<String, dynamic> toJson() => {
    'serviceId': serviceId,
    'professionalId': professionalId,
    'startAt': toIsoSp(startAt),
    if (client != null) 'client': client!.toJson(),
  };

  @override
  List<Object?> get props => [serviceId, professionalId, startAt, client];
}

/// `ClientBookingCreated` do contrato.
class ClientBookingCreated extends Equatable {
  const ClientBookingCreated({required this.booking, this.clientCode});

  factory ClientBookingCreated.fromJson(Map<String, dynamic> j) =>
      ClientBookingCreated(
        booking: Booking.fromJson(j['booking'] as Map<String, dynamic>),
        clientCode: j['clientCode'] as String?,
      );

  final Booking booking;

  /// Só no primeiro agendamento do aparelho. Guardar e nunca mostrar na tela.
  final String? clientCode;

  Map<String, dynamic> toJson() => {
    'booking': booking.toJson(),
    'clientCode': clientCode,
  };

  @override
  List<Object?> get props => [booking, clientCode];
}
