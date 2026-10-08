/// Códigos estáveis de erro do contrato (`ErrorCode` em `api/openapi.yaml`).
enum ErrorCode {
  unauthorized('UNAUTHORIZED'),
  forbidden('FORBIDDEN'),
  notFound('NOT_FOUND'),
  validationError('VALIDATION_ERROR'),
  slotTaken('SLOT_TAKEN'),
  tooSoon('TOO_SOON'),
  outsideWorkingHours('OUTSIDE_WORKING_HOURS'),
  bookingLimitReached('BOOKING_LIMIT_REACHED'),
  cancelWindowClosed('CANCEL_WINDOW_CLOSED'),
  invalidStatusTransition('INVALID_STATUS_TRANSITION'),
  phoneInUse('PHONE_IN_USE'),
  emailInUse('EMAIL_IN_USE'),
  timeOffHasBookings('TIME_OFF_HAS_BOOKINGS'),
  commissionSumInvalid('COMMISSION_SUM_INVALID'),
  dateOutOfRange('DATE_OUT_OF_RANGE'),
  tooEarly('TOO_EARLY'),
  slotInPast('SLOT_IN_PAST'),
  professionalHasFutureBookings('PROFESSIONAL_HAS_FUTURE_BOOKINGS'),
  idempotencyKeyReused('IDEMPOTENCY_KEY_REUSED');

  const ErrorCode(this.wire);
  final String wire;

  static ErrorCode fromWire(String raw) => ErrorCode.values.firstWhere(
    (c) => c.wire == raw,
    orElse: () => ErrorCode.validationError,
  );
}

class ProblemField {
  const ProblemField(this.field, this.message);
  final String field;
  final String message;
}

/// Erro no formato `Problem` (RFC 7807). O mock e o cliente da API jogam este
/// mesmo tipo, então a tela escolhe a mensagem só pelo [code].
class ApiProblem implements Exception {
  const ApiProblem(
    this.code, {
    required this.status,
    this.title = '',
    this.fields = const [],
  });

  final ErrorCode code;
  final int status;
  final String title;
  final List<ProblemField> fields;

  bool hasField(String name) => fields.any((f) => f.field == name);

  @override
  String toString() => 'ApiProblem(${code.wire}, $status, $title)';
}

/// Mensagem que o app Cliente mostra para cada código.
String clientMessageFor(ApiProblem p) {
  switch (p.code) {
    case ErrorCode.slotTaken:
      return 'Esse horário acabou de ficar indisponível';
    case ErrorCode.tooSoon:
      return 'Esse horário já não dá mais. Marque com pelo menos 30 minutos de antecedência.';
    case ErrorCode.bookingLimitReached:
      return 'Você já tem 2 horários marcados. Cancele um para marcar outro.';
    case ErrorCode.cancelWindowClosed:
      return 'Faltam menos de 2 horas. O cancelamento agora é só com a barbearia.';
    case ErrorCode.invalidStatusTransition:
      return 'Esse horário mudou de status. A lista foi atualizada.';
    case ErrorCode.slotInPast:
      return 'Esse horário já passou.';
    case ErrorCode.dateOutOfRange:
      return 'A agenda abre só para os próximos 14 dias.';
    case ErrorCode.outsideWorkingHours:
      return 'Esse horário está fora do expediente do profissional.';
    case ErrorCode.unauthorized:
      return 'Não deu para identificar este aparelho. Marque um horário para continuar.';
    case ErrorCode.notFound:
      return 'Não encontramos isso. Volte e tente de novo.';
    case ErrorCode.validationError:
      if (p.hasField('phone')) {
        return 'Telefone inválido. Use DDD + número, ex.: (11) 98765-4321.';
      }
      if (p.hasField('name')) return 'Escreva seu nome (mínimo 2 letras).';
      return 'Confira os dados e tente de novo.';
    default:
      return 'Algo deu errado. Tente de novo.';
  }
}
