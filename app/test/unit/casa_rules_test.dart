import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:cortaaqui/domain/casa_rules.dart';
import 'package:cortaaqui/domain/scheduling.dart';
import 'package:cortaaqui/presentation/casa/casa_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CT-07-08/09 expediente: 08:00–21:00 e grade de 30 min', () {
    expect(checkWorkWindow(WorkWindow.hm('08:00', '21:00')), isNull);
    expect(checkWorkWindow(WorkWindow.hm('08:30', '18:30')), isNull);
    for (final w in [
      WorkWindow.hm('07:30', '18:00'),
      WorkWindow.hm('09:00', '21:30'),
      WorkWindow.hm('08:15', '18:00'),
      WorkWindow.hm('08:00', '17:45'),
    ]) {
      expect(checkWorkWindow(w)?.code, ErrorCode.validationError);
    }
  });

  test('janelas sobrepostas ou mais de 3 por dia: recusa', () {
    expect(
      checkDayWindows([
        WorkWindow.hm('08:00', '12:00'),
        WorkWindow.hm('11:30', '14:00'),
      ]),
      isNotNull,
    );
    expect(
      checkDayWindows([
        WorkWindow.hm('08:00', '12:00'),
        WorkWindow.hm('13:00', '18:00'),
      ]),
      isNull,
    );
  });

  test('CT-10-07 duração 30..480 em múltiplos de 30', () {
    for (final ok in [30, 60, 90, 480]) {
      expect(checkServiceDuration(ok), isNull, reason: '$ok');
    }
    for (final bad in [0, -30, 45, 510]) {
      expect(checkServiceDuration(bad), isNotNull, reason: '$bad');
    }
  });

  test('CT-20-02/03 % soma 100, inteiro de 0 a 100', () {
    expect(checkSplit(30, 70), isNull);
    expect(checkSplit(0, 100), isNull);
    expect(checkSplit(40, 70)?.code, ErrorCode.commissionSumInvalid);
    expect(checkSplit(-1, 101)?.code, ErrorCode.validationError);
  });

  test('textos exatos do PO na Casa', () {
    expect(
      casaMessageFor(const ApiProblem(ErrorCode.concurrentUpdate, status: 409)),
      'Não deu pra concluir agora. Tente de novo.',
    );
    expect(
      casaMessageFor(const ApiProblem(ErrorCode.slotTaken, status: 409)),
      'Horário ocupado',
    );
    expect(
      casaMessageFor(const ApiProblem(ErrorCode.statusChanged, status: 409)),
      kStatusChangedMessage,
    );
  });
}
