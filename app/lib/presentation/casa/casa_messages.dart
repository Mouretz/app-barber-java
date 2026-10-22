import '../../core/errors/api_problem.dart';

/// Texto do login recusado: o mesmo para senha errada, e-mail desconhecido e
/// profissional sem vínculo ativo (o servidor não diz qual foi).
const kLoginFailedMessage = 'E-mail ou senha incorretos.';

/// Status mudou em outra tela (CT-02-23, CT-00-45).
const kStatusChangedMessage =
    'Esse horário já tinha mudado. A agenda foi atualizada.';

/// Mensagem que o app Casa mostra para cada código.
String casaMessageFor(ApiProblem p) {
  switch (p.code) {
    case ErrorCode.slotTaken:
      return kSlotTakenMessage;
    case ErrorCode.concurrentUpdate:
      return kConcurrentUpdateMessage;
    case ErrorCode.statusChanged:
      return kStatusChangedMessage;
    case ErrorCode.tooEarly:
      return 'Só dá pra concluir ou marcar falta a partir do horário de início.';
    case ErrorCode.slotInPast:
      return 'Esse horário já passou.';
    case ErrorCode.dateOutOfRange:
      return 'A agenda abre só para os próximos 14 dias.';
    case ErrorCode.outsideWorkingHours:
      return 'Esse horário está fora do expediente do profissional.';
    case ErrorCode.deviceReleaseNotAllowed:
      return 'Só dá pra liberar o aparelho de quem já agendou pelo app nesta barbearia.';
    case ErrorCode.phoneInUse:
      return 'Já existe um cliente com esse telefone aqui.';
    case ErrorCode.professionalHasFutureBookings:
      return 'Esse profissional tem horários marcados. Cancele antes de desativar.';
    case ErrorCode.commissionSumInvalid:
      return 'A soma do profissional e da casa tem que dar 100.';
    case ErrorCode.forbidden:
      return 'Você não tem permissão para isso.';
    case ErrorCode.unauthorized:
      return 'Sua sessão terminou. Entre de novo.';
    case ErrorCode.notFound:
      return 'Não encontramos isso. Volte e tente de novo.';
    case ErrorCode.validationError:
      if (p.fields.any((f) => f.field.contains('phone'))) {
        return 'Telefone inválido. Use DDD + número, ex.: (11) 98765-4321.';
      }
      if (p.fields.any((f) => f.field.contains('name'))) {
        return 'Escreva o nome (mínimo 2 letras).';
      }
      if (p.hasField('durationMinutes')) {
        return 'A duração vai de 30 a 480 min, de 30 em 30.';
      }
      if (p.fields.any((f) => f.field.contains('windows'))) {
        return 'O expediente vai de 08:00 a 21:00, de 30 em 30 min.';
      }
      if (p.fields.any((f) => f.field.contains('Percent'))) {
        return 'Use números inteiros de 0 a 100.';
      }
      return 'Confira os dados e tente de novo.';
    default:
      return 'Algo deu errado. Tente de novo.';
  }
}
