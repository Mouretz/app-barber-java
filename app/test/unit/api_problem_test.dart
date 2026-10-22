import 'package:cortaaqui/core/errors/api_problem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CONCURRENT_UPDATE: texto do PO e código do servidor', () {
    expect(ErrorCode.fromWire('CONCURRENT_UPDATE'), ErrorCode.concurrentUpdate);
    expect(
      clientMessageFor(
        const ApiProblem(ErrorCode.concurrentUpdate, status: 409),
      ),
      'Não deu pra concluir agora. Tente de novo.',
    );
  });

  test('SLOT_TAKEN: "Horário ocupado"', () {
    expect(
      clientMessageFor(const ApiProblem(ErrorCode.slotTaken, status: 409)),
      'Horário ocupado',
    );
  });
}
