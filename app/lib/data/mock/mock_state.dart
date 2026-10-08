import '../../core/time/sao_paulo.dart';
import '../../domain/scheduling.dart';
import '../models/barbershop.dart';
import '../models/booking.dart';

/// Barbearia do seed com o expediente de cada profissional (não muda no app
/// Cliente, então não é gravada no aparelho).
class MockShop {
  const MockShop({required this.detail, required this.weeklyHours});

  final BarbershopDetail detail;

  /// professionalId -> dia da semana (1 = seg ... 7 = dom) -> janelas.
  /// Dia ausente é folga fixa.
  final Map<String, Map<int, List<WorkWindow>>> weeklyHours;

  List<WorkWindow> windowsFor(String professionalId, SpDate date) =>
      weeklyHours[professionalId]?[date.weekday] ?? const [];
}

/// Cadastro global do cliente (um por telefone normalizado), com uma ficha por
/// barbearia (nome que aquela barbearia vê).
class MockClient {
  MockClient({
    required this.id,
    required this.phone,
    required this.name,
    required this.createdAt,
    Map<String, String>? fichaNames,
  }) : fichaNames = fichaNames ?? {};

  factory MockClient.fromJson(Map<String, dynamic> j) => MockClient(
    id: j['id'] as String,
    phone: j['phone'] as String,
    name: j['name'] as String,
    createdAt: parseInstant(j['createdAt'] as String),
    fichaNames: (j['fichaNames'] as Map).cast<String, String>(),
  );

  final String id;
  final String phone;
  final String name;
  final DateTime createdAt;

  /// barbershopId -> nome na ficha daquela barbearia.
  final Map<String, String> fichaNames;

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'name': name,
    'createdAt': toIsoSp(createdAt),
    'fichaNames': fichaNames,
  };
}

class MockBlock {
  const MockBlock({
    required this.id,
    required this.barbershopId,
    required this.professionalId,
    required this.startAt,
    required this.endAt,
  });

  factory MockBlock.fromJson(Map<String, dynamic> j) => MockBlock(
    id: j['id'] as String,
    barbershopId: j['barbershopId'] as String,
    professionalId: j['professionalId'] as String,
    startAt: parseInstant(j['startAt'] as String),
    endAt: parseInstant(j['endAt'] as String),
  );

  final String id;
  final String barbershopId;
  final String professionalId;
  final DateTime startAt;
  final DateTime endAt;

  TimeSpan get span => TimeSpan(startAt, endAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'barbershopId': barbershopId,
    'professionalId': professionalId,
    'startAt': toIsoSp(startAt),
    'endAt': toIsoSp(endAt),
  };
}

/// Resposta guardada para um `Idempotency-Key`.
class MockIdempotencyEntry {
  const MockIdempotencyEntry({
    required this.fingerprint,
    required this.bookingId,
    this.clientCode,
  });

  factory MockIdempotencyEntry.fromJson(Map<String, dynamic> j) =>
      MockIdempotencyEntry(
        fingerprint: j['fingerprint'] as String,
        bookingId: j['bookingId'] as String,
        clientCode: j['clientCode'] as String?,
      );

  final String fingerprint;
  final String bookingId;
  final String? clientCode;

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'bookingId': bookingId,
    'clientCode': clientCode,
  };
}

/// O "banco" do mock. Só a parte que muda é gravada no aparelho.
class MockState {
  MockState({
    required this.shops,
    List<MockClient>? clients,
    Map<String, String>? codes,
    List<Booking>? bookings,
    List<MockBlock>? blocks,
    Map<String, MockIdempotencyEntry>? idempotency,
  }) : clients = clients ?? [],
       codes = codes ?? {},
       bookings = bookings ?? [],
       blocks = blocks ?? [],
       idempotency = idempotency ?? {};

  final List<MockShop> shops;
  final List<MockClient> clients;

  /// Código do aparelho -> id do cliente.
  final Map<String, String> codes;
  final List<Booking> bookings;
  final List<MockBlock> blocks;
  final Map<String, MockIdempotencyEntry> idempotency;

  /// Versão 2: telefone no formato `+55...`. Estado salvo de outra versão é
  /// descartado e o seed é montado de novo.
  static const int schemaVersion = 2;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'clients': clients.map((c) => c.toJson()).toList(),
    'codes': codes,
    'bookings': bookings.map((b) => b.toJson()).toList(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'idempotency': idempotency.map((k, v) => MapEntry(k, v.toJson())),
  };

  /// Devolve `null` se o formato gravado for de outra versão.
  static MockState? fromJson(List<MockShop> shops, Map<String, dynamic> j) {
    if (j['version'] != schemaVersion) return null;
    return MockState(
      shops: shops,
      clients: (j['clients'] as List)
          .map((e) => MockClient.fromJson(e as Map<String, dynamic>))
          .toList(),
      codes: (j['codes'] as Map).cast<String, String>(),
      bookings: (j['bookings'] as List)
          .map((e) => Booking.fromJson(e as Map<String, dynamic>))
          .toList(),
      blocks: (j['blocks'] as List)
          .map((e) => MockBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
      idempotency: (j['idempotency'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          MockIdempotencyEntry.fromJson(v as Map<String, dynamic>),
        ),
      ),
    );
  }
}
