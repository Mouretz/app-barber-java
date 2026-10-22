import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';
import '../models/staff.dart';
import 'mock_seed.dart';

/// Vínculo de uma pessoa da Casa com uma barbearia, do jeito que o "servidor"
/// do mock guarda.
class MockMembership {
  MockMembership({
    required this.barbershopId,
    required this.roles,
    this.professionalId,
    this.formerProfessionalId,
    this.active = true,
  });

  factory MockMembership.fromJson(Map<String, dynamic> j) => MockMembership(
    barbershopId: j['barbershopId'] as String,
    roles: (j['roles'] as List)
        .map((e) => StaffRole.fromWire(e as String))
        .toSet(),
    professionalId: j['professionalId'] as String?,
    formerProfessionalId: j['formerProfessionalId'] as String?,
    active: j['active'] as bool,
  );

  final String barbershopId;
  Set<StaffRole> roles;
  String? professionalId;

  /// Profissional desativado: guarda o id para o vínculo voltar na reativação.
  String? formerProfessionalId;

  /// `false` para o profissional (não gerente) desativado nesta barbearia.
  bool active;

  bool get isManager => roles.contains(StaffRole.manager);

  Map<String, dynamic> toJson() => {
    'barbershopId': barbershopId,
    'roles': roles.map((r) => r.wire).toList(),
    'professionalId': professionalId,
    'formerProfessionalId': formerProfessionalId,
    'active': active,
  };
}

/// Login da Casa no mock. A senha existe só no seed do mock (nunca é segredo
/// de verdade) e não sai do "servidor" do mock.
class MockStaff {
  MockStaff({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.memberships,
  });

  factory MockStaff.fromJson(Map<String, dynamic> j) => MockStaff(
    id: j['id'] as String,
    name: j['name'] as String,
    email: j['email'] as String,
    password: j['password'] as String,
    memberships: (j['memberships'] as List)
        .map((e) => MockMembership.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String name;
  final String email;
  final String password;
  final List<MockMembership> memberships;

  bool get hasActiveLink => memberships.any((m) => m.active);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'password': password,
    'memberships': memberships.map((m) => m.toJson()).toList(),
  };
}

/// O que só o app Casa usa no mock: logins, equipe (com ativo), expediente,
/// folgas, serviços editáveis, % e tokens. As marcações, bloqueios e clientes
/// ficam no `MockState`, igual ao app Cliente.
class MockCasaState {
  MockCasaState({
    required this.staff,
    required this.professionals,
    required this.weeklyHours,
    required this.services,
    required this.commission,
    List<TimeOff>? timeOff,
    Map<String, String>? tokens,
    Map<String, String>? clientEmails,
  }) : timeOff = timeOff ?? [],
       tokens = tokens ?? {},
       clientEmails = clientEmails ?? {};

  final List<MockStaff> staff;

  /// barbershopId -> profissionais (inclui inativos).
  final Map<String, List<Professional>> professionals;

  /// professionalId -> weekday -> janelas.
  final Map<String, Map<int, List<WorkWindow>>> weeklyHours;

  /// barbershopId -> serviços (inclui inativos).
  final Map<String, List<Service>> services;

  /// barbershopId -> divisão.
  final Map<String, CommissionSettings> commission;
  final List<TimeOff> timeOff;

  /// token -> staffId.
  final Map<String, String> tokens;

  /// "barbershopId|clientId" -> e-mail da ficha.
  final Map<String, String> clientEmails;

  static const int schemaVersion = 1;

  List<WorkWindow> windowsFor(String professionalId, SpDate date) {
    final dayStart = date.at(0);
    final dayEnd = date.addDays(1).at(0);
    final off = timeOff.any(
      (t) =>
          t.professionalId == professionalId &&
          !t.startAt.isAfter(dayStart) &&
          !t.endAt.isBefore(dayEnd),
    );
    if (off) return const [];
    return weeklyHours[professionalId]?[date.weekday] ?? const [];
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'staff': staff.map((s) => s.toJson()).toList(),
    'professionals': professionals.map(
      (k, v) => MapEntry(
        k,
        v
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'active': p.active,
                'email': p.email,
              },
            )
            .toList(),
      ),
    ),
    'weeklyHours': weeklyHours.map(
      (k, v) => MapEntry(
        k,
        v.map(
          (d, ws) => MapEntry(
            '$d',
            ws.map((w) => [w.startMinute, w.endMinute]).toList(),
          ),
        ),
      ),
    ),
    'services': services.map(
      (k, v) => MapEntry(k, v.map((x) => x.toJson()).toList()),
    ),
    'commission': commission.map(
      (k, v) => MapEntry(k, {
        'default': [v.standard.shopPercent, v.standard.professionalPercent],
        'professionals': v.professionals.map(
          (id, s) => MapEntry(id, [s.shopPercent, s.professionalPercent]),
        ),
      }),
    ),
    'timeOff': timeOff
        .map(
          (t) => {
            'id': t.id,
            'professionalId': t.professionalId,
            'startAt': toIsoSp(t.startAt),
            'endAt': toIsoSp(t.endAt),
          },
        )
        .toList(),
    'tokens': tokens,
    'clientEmails': clientEmails,
  };

  static MockCasaState? fromJson(Map<String, dynamic> j) {
    if (j['version'] != schemaVersion) return null;
    CommissionSplit split(List l) => CommissionSplit(
      shopPercent: l[0] as int,
      professionalPercent: l[1] as int,
    );
    return MockCasaState(
      staff: (j['staff'] as List)
          .map((e) => MockStaff.fromJson(e as Map<String, dynamic>))
          .toList(),
      professionals: (j['professionals'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as List)
              .map(
                (p) => Professional(
                  id: p['id'] as String,
                  name: p['name'] as String,
                  active: p['active'] as bool,
                  email: p['email'] as String?,
                ),
              )
              .toList(),
        ),
      ),
      weeklyHours: (j['weeklyHours'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as Map).map(
            (d, ws) => MapEntry(
              int.parse(d as String),
              (ws as List)
                  .map((w) => WorkWindow(w[0] as int, w[1] as int))
                  .toList(),
            ),
          ),
        ),
      ),
      services: (j['services'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as List)
              .map((x) => Service.fromJson(x as Map<String, dynamic>))
              .toList(),
        ),
      ),
      commission: (j['commission'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          CommissionSettings(
            standard: split(v['default'] as List),
            professionals: (v['professionals'] as Map).map(
              (id, s) => MapEntry(id as String, split(s as List)),
            ),
          ),
        ),
      ),
      timeOff: (j['timeOff'] as List)
          .map(
            (t) => TimeOff(
              id: t['id'] as String,
              professionalId: t['professionalId'] as String,
              startAt: parseInstant(t['startAt'] as String),
              endAt: parseInstant(t['endAt'] as String),
            ),
          )
          .toList(),
      tokens: (j['tokens'] as Map).cast<String, String>(),
      clientEmails: (j['clientEmails'] as Map).cast<String, String>(),
    );
  }
}

/// Seed do app Casa (só mock). Mesma Barbearia Navalha, Caio e Helena do
/// [MockSeed], mais os logins da Casa:
/// - Marina: gerente que não atende (`professionalId` = `null`);
/// - Caio: gerente e profissional;
/// - Helena: só profissional.
///
/// As senhas valem só no mock e aparecem na tela de login do APK mock.
abstract final class MockCasaSeed {
  static const marinaId = '6f1c2a10-0000-4000-8000-0000000000f1';
  static const caioUserId = '6f1c2a10-0000-4000-8000-0000000000f2';
  static const helenaUserId = '6f1c2a10-0000-4000-8000-0000000000f3';

  static const marinaEmail = 'gerente@navalha.mock';
  static const caioEmail = 'caio@navalha.mock';
  static const helenaEmail = 'helena@navalha.mock';

  /// Senha de todos os logins do seed. Só existe no mock.
  static const mockPassword = 'cortaaqui-mock';

  static MockCasaState build() => MockCasaState(
    staff: [
      MockStaff(
        id: marinaId,
        name: 'Marina Costa',
        email: marinaEmail,
        password: mockPassword,
        memberships: [
          MockMembership(
            barbershopId: MockSeed.shopId,
            roles: {StaffRole.manager},
          ),
        ],
      ),
      MockStaff(
        id: helenaUserId,
        name: 'Helena',
        email: helenaEmail,
        password: mockPassword,
        memberships: [
          MockMembership(
            barbershopId: MockSeed.shopId,
            roles: {StaffRole.professional},
            professionalId: MockSeed.helenaId,
          ),
        ],
      ),
      MockStaff(
        id: caioUserId,
        name: 'Caio',
        email: caioEmail,
        password: mockPassword,
        memberships: [
          MockMembership(
            barbershopId: MockSeed.shopId,
            roles: {StaffRole.manager, StaffRole.professional},
            professionalId: MockSeed.caioId,
          ),
        ],
      ),
    ],
    professionals: {
      MockSeed.shopId: [
        const Professional(
          id: MockSeed.caioId,
          name: 'Caio',
          active: true,
          email: caioEmail,
        ),
        const Professional(
          id: MockSeed.helenaId,
          name: 'Helena',
          active: true,
          email: helenaEmail,
        ),
      ],
    },
    weeklyHours: {
      for (final e in MockSeed.weeklyHours.entries)
        e.key: {
          for (final d in e.value.entries) d.key: [...d.value],
        },
    },
    services: {
      MockSeed.shopId: [...MockSeed.navalha.services],
    },
    commission: {
      MockSeed.shopId: const CommissionSettings(
        standard: CommissionSplit.standard,
        professionals: {},
      ),
    },
  );

  /// Concluído do seed sem % gravada (o app Cliente não vê a %): grava o padrão
  /// 60/40, como o servidor teria gravado na conclusão.
  static List<Booking> withSeedPercents(List<Booking> bookings) => [
    for (final b in bookings)
      b.status == BookingStatus.completed && b.professionalPercent == null
          ? b.copyWith(shopPercent: 40, professionalPercent: 60)
          : b,
  ];
}
