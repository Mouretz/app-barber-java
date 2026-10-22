import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../data/models/barbershop.dart';
import '../../../theme/theme.dart';
import '../providers.dart';
import '../widgets/common.dart';

/// História 16. Serviços (preço e duração) e profissionais. Tocar num serviço
/// ou profissional abre o Agendar com ele já escolhido.
class BarbershopScreen extends ConsumerWidget {
  const BarbershopScreen({super.key, required this.barbershopId});

  final String barbershopId;

  void _book(BuildContext context, {String? serviceId, String? proId}) {
    final q = <String, String>{
      if (serviceId != null) 'servico': serviceId,
      if (proId != null) 'profissional': proId,
    };
    final uri = Uri(path: '/agendar/$barbershopId', queryParameters: q);
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(barbershopProvider(barbershopId));
    return Scaffold(
      appBar: AppBar(),
      body: shop.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(
          error: e,
          onRetry: () => ref.invalidate(barbershopProvider(barbershopId)),
        ),
        data: (d) => _Body(
          shop: d,
          onService: (s) => _book(context, serviceId: s.id),
          onPro: (p) => _book(context, proId: p.id),
        ),
      ),
      bottomNavigationBar: shop.hasValue
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: () => _book(context),
                child: const Text('Agendar'),
              ),
            )
          : null,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.shop,
    required this.onService,
    required this.onPro,
  });

  final BarbershopDetail shop;
  final ValueChanged<Service> onService;
  final ValueChanged<ProfessionalPublic> onPro;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(shop.name, style: text.headlineLarge),
        const SizedBox(height: 6),
        Text(shop.address, style: text.bodySmall),
        const SizedBox(height: 28),
        const SectionLabel('Serviços'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < shop.services.length; i++) ...[
                if (i > 0) Divider(color: t.border, indent: 16),
                InkWell(
                  key: ValueKey('shop-service-${shop.services[i].id}'),
                  onTap: () => onService(shop.services[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.services[i].name,
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatDuration(
                                  shop.services[i].durationMinutes,
                                ),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatCents(shop.services[i].priceCents),
                          style: text.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionLabel('Profissionais'),
        Wrap(
          spacing: 18,
          runSpacing: 12,
          children: [
            for (final p in shop.professionals)
              InkWell(
                key: ValueKey('shop-pro-${p.id}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => onPro(p),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      ProAvatar(name: p.name, size: 64),
                      const SizedBox(height: 6),
                      Text(p.name, style: text.labelLarge),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
