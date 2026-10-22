import 'package:cortaaqui/core/time/clock.dart';
import 'package:cortaaqui/data/mock/mock_seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const page = '/inicio/barbearia/${MockSeed.shopId}';

void main() {
  testWidgets('CT-16-01 serviços com preço e duração e os 2 profissionais', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: page,
    );
    expect(find.text('Barbearia Navalha'), findsOneWidget);
    for (final s in ['Corte', 'Barba', 'Corte + Barba']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('30 min'), findsNWidgets(2));
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('R\$ 40,00'), findsOneWidget);
    expect(find.text('R\$ 30,00'), findsOneWidget);
    expect(find.text('R\$ 60,00'), findsOneWidget);
    expect(find.text('Caio'), findsOneWidget);
    expect(find.text('Helena'), findsOneWidget);
  });

  testWidgets('CT-16-05 sem nota, avaliações, favoritar, pontos ou pagamento', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: page,
    );
    for (final s in ['Avalia', 'Favorit', 'Pontos', 'Pagamento', 'Nota']) {
      expect(find.textContaining(s), findsNothing, reason: s);
    }
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('CT-16-04 tocar num serviço abre o Agendar com ele escolhido', (
    tester,
  ) async {
    final clock = FixedClock(kNow);
    await pumpCliente(
      tester,
      repo: seededRepo(clock),
      clock: clock,
      location: page,
    );
    await tester.tap(
      find.byKey(const ValueKey('shop-service-${MockSeed.barbaId}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Agendar'), findsOneWidget); // título
    final option = find.byKey(const ValueKey('service-${MockSeed.barbaId}'));
    expect(
      find.descendant(of: option, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
  });

  testWidgets(
    'CT-16-04 tocar num profissional abre o Agendar com ele escolhido',
    (tester) async {
      final clock = FixedClock(kNow);
      await pumpCliente(
        tester,
        repo: seededRepo(clock),
        clock: clock,
        location: page,
      );
      await tester.tap(
        find.byKey(const ValueKey('shop-pro-${MockSeed.helenaId}')),
      );
      await tester.pumpAndSettle();
      expect(yellowTexts(tester), ['Helena']);
    },
  );
}
