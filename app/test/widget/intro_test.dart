import 'package:cortaaqui/core/storage/device_store.dart';
import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

const t = CortaTokens.dark;

Color dotColor(WidgetTester tester, int i) {
  final c = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('intro-dot-$i')),
  );
  return (c.decoration! as BoxDecoration).color!;
}

void expectActiveDot(WidgetTester tester, int active) {
  for (var i = 0; i < 3; i++) {
    expect(
      dotColor(tester, i),
      i == active ? t.accent : isNot(t.accent),
      reason: 'ponto $i',
    );
  }
}

void main() {
  testWidgets('CT-14-01 / CT-09-05 três telas, só o ponto ativo amarelo, '
      'rótulo e Próximo brancos', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      introSeen: false,
    );

    expect(find.text('Sem fila e sem ligação'), findsOneWidget);
    expectActiveDot(tester, 0);

    final label = tester.widget<Text>(
      find.byKey(const ValueKey('intro-label-0')),
    );
    expect(label.style!.color, t.text);
    final next = tester.widget<TextButton>(
      find.byKey(const ValueKey('intro-next')),
    );
    expect(next.style!.foregroundColor!.resolve({}), t.text);
    expect(find.text('Próximo'), findsOneWidget);
    expect(yellowTexts(tester), isEmpty);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('Corte com quem você confia'), findsOneWidget);
    expectActiveDot(tester, 1);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('Tudo na palma da mão'), findsOneWidget);
    expectActiveDot(tester, 2);
    expect(find.text('Começar'), findsOneWidget);
  });

  testWidgets('CT-14-02 o botão final vai para o Início e grava que viu', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      introSeen: false,
    );
    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();

    expect(find.text('Barbearia Navalha'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DeviceStore.kIntroSeen), isTrue);
  });

  testWidgets('CT-14-03 Pular vai direto para o Início', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      introSeen: false,
    );
    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    expect(find.text('Barbearia Navalha'), findsOneWidget);
    expect(find.text('Sem fila e sem ligação'), findsNothing);
  });

  testWidgets('CT-14-04 intro já vista: abre direto no Início', (tester) async {
    final clock = FixedClock(kNow);
    await pumpCliente(tester, repo: seededRepo(clock), clock: clock);
    expect(find.text('Sem fila e sem ligação'), findsNothing);
    expect(find.text('Barbearia Navalha'), findsOneWidget);
  });
}
