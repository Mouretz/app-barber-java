import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/format/formatters.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/staff.dart';
import '../../../theme/theme.dart';
import '../../cliente/widgets/common.dart';
import '../casa_messages.dart';
import '../providers.dart';

/// Caixa do mês (história 8). Gerente: caixa da casa com todas as linhas e a
/// parte da casa. Profissional que não é gerente: "Meus ganhos", só a linha
/// dele, sem parte da casa.
class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider)!;
    final month = monthKey(SpDate.of(ref.watch(clockProvider).now()));
    final cash = ref.watch(cashProvider(month));
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text(month, style: text.labelSmall),
        const SizedBox(height: 6),
        Text(
          session.isManager ? 'Caixa da casa' : 'Meus ganhos',
          key: const ValueKey('cash-title'),
          style: text.displaySmall,
        ),
        const SizedBox(height: 16),
        cash.when(
          loading: () => const LoadingBox(),
          error: (e, _) => Text(
            e is ApiProblem ? casaMessageFor(e) : 'Não deu para carregar.',
            style: text.bodySmall,
          ),
          data: (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalsCard(
                key: const ValueKey('cash-totals'),
                title: session.isManager ? 'Total do mês' : 'Meu mês',
                totals: c.totals,
              ),
              if (session.isManager) ...[
                const SizedBox(height: 16),
                const SectionLabel('Por profissional'),
                for (final r in c.byProfessional)
                  _TotalsCard(
                    key: ValueKey('cash-row-${r.professional.id}'),
                    title: r.professional.name,
                    totals: r.totals,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({super.key, required this.title, required this.totals});

  final String title;
  final CashTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    Widget line(String label, int cents) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: t.textMuted),
            ),
          ),
          Text(
            formatCents(cents),
            style: text.bodyMedium?.copyWith(color: t.text),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleSmall),
            Text(
              '${totals.completedCount} atendimento(s) concluído(s)',
              style: text.bodySmall?.copyWith(color: t.textMuted),
            ),
            line('Bruto', totals.grossCents),
            line('Profissional', totals.professionalCents),
            // Só o gerente recebe a parte da casa (o campo nem vem pro
            // profissional).
            if (totals.shopCents != null) line('Casa', totals.shopCents!),
          ],
        ),
      ),
    );
  }
}
