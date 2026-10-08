import 'package:equatable/equatable.dart';

/// `Service` do contrato.
class Service extends Equatable {
  const Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.priceCents,
    required this.active,
  });

  factory Service.fromJson(Map<String, dynamic> j) => Service(
    id: j['id'] as String,
    name: j['name'] as String,
    durationMinutes: j['durationMinutes'] as int,
    priceCents: j['priceCents'] as int,
    active: j['active'] as bool,
  );

  final String id;
  final String name;
  final int durationMinutes;
  final int priceCents;
  final bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'durationMinutes': durationMinutes,
    'priceCents': priceCents,
    'active': active,
  };

  @override
  List<Object?> get props => [id, name, durationMinutes, priceCents, active];
}

/// `ProfessionalPublic` do contrato.
class ProfessionalPublic extends Equatable {
  const ProfessionalPublic({
    required this.id,
    required this.name,
    this.photoUrl,
  });

  factory ProfessionalPublic.fromJson(Map<String, dynamic> j) =>
      ProfessionalPublic(
        id: j['id'] as String,
        name: j['name'] as String,
        photoUrl: j['photoUrl'] as String?,
      );

  final String id;
  final String name;
  final String? photoUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'photoUrl': photoUrl,
  };

  @override
  List<Object?> get props => [id, name, photoUrl];
}

/// `BarbershopSummary` do contrato (tela Início, história 15).
class BarbershopSummary extends Equatable {
  const BarbershopSummary({
    required this.id,
    required this.name,
    required this.neighborhood,
    required this.city,
    this.coverUrl,
    this.startingPriceCents,
  });

  factory BarbershopSummary.fromJson(Map<String, dynamic> j) =>
      BarbershopSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        neighborhood: j['neighborhood'] as String,
        city: j['city'] as String,
        coverUrl: j['coverUrl'] as String?,
        startingPriceCents: j['startingPriceCents'] as int?,
      );

  final String id;
  final String name;
  final String neighborhood;
  final String city;
  final String? coverUrl;
  final int? startingPriceCents;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'neighborhood': neighborhood,
    'city': city,
    'coverUrl': coverUrl,
    'startingPriceCents': startingPriceCents,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    neighborhood,
    city,
    coverUrl,
    startingPriceCents,
  ];
}

/// `BarbershopDetail` do contrato (página da barbearia, história 16).
class BarbershopDetail extends BarbershopSummary {
  const BarbershopDetail({
    required super.id,
    required super.name,
    required super.neighborhood,
    required super.city,
    super.coverUrl,
    super.startingPriceCents,
    required this.address,
    this.phone,
    required this.services,
    required this.professionals,
  });

  factory BarbershopDetail.fromJson(Map<String, dynamic> j) => BarbershopDetail(
    id: j['id'] as String,
    name: j['name'] as String,
    neighborhood: j['neighborhood'] as String,
    city: j['city'] as String,
    coverUrl: j['coverUrl'] as String?,
    startingPriceCents: j['startingPriceCents'] as int?,
    address: j['address'] as String,
    phone: j['phone'] as String?,
    services: (j['services'] as List)
        .map((e) => Service.fromJson(e as Map<String, dynamic>))
        .toList(),
    professionals: (j['professionals'] as List)
        .map((e) => ProfessionalPublic.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String address;
  final String? phone;
  final List<Service> services;
  final List<ProfessionalPublic> professionals;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'address': address,
    'phone': phone,
    'services': services.map((s) => s.toJson()).toList(),
    'professionals': professionals.map((p) => p.toJson()).toList(),
  };

  @override
  List<Object?> get props => [
    ...super.props,
    address,
    phone,
    services,
    professionals,
  ];
}
