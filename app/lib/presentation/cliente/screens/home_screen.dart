import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../core/phone/phone.dart';
import '../../../core/storage/device_store.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/barbershop.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../theme/theme.dart';
import '../providers.dart';
import '../widgets/booking_card.dart';
import '../widgets/common.dart';
import 'register_phone_sheet.dart';

/// História 15. Próximo horário do cliente e lista de barbearias.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(barbershopsProvider);
    ref.invalidate(myBookingsProvider(BookingScope.upcoming));
    await ref.read(barbershopsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final shops = ref.watch(barbershopsProvider);
    final next = ref.watch(nextBookingProvider);
    final device = ref.watch(deviceStoreProvider);
    final today = SpDate.of(ref.watch(clockProvider).now());

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Text('CORTAAQUI', style: text.labelSmall),
              const SizedBox(height: 6),
              Text('Início', style: text.displaySmall),
              const SizedBox(height: 28),
              if (device.hydrated && device.phoneOnFile == null) ...[
                _RegisterPhoneInfo(
                  onTap: () => showRegisterPhoneSheet(context, ref),
                ),
                const SizedBox(height: 28),
              ],
              if (device.hydrated &&
                  !device.hasSession &&
                  device.draftPhone != null) ...[
                SurfaceCard(
                  key: const ValueKey('home-phone-saved'),
                  child: Text(
                    'Telefone cadastrado: ${formatPhone(device.draftPhone!)}.',
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(height: 28),
              ],
              const SectionLabel('Próximo horário'),
              next.when(
                loading: () => const LoadingBox(height: 110),
                error: (e, _) => ErrorBox(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(myBookingsProvider(BookingScope.upcoming)),
                ),
                data: (b) => b == null
                    ? _EmptyNext(
                        firstShopId: shops.valueOrNull?.firstOrNull?.id,
                      )
                    : BookingCard(
                        key: const ValueKey('home-next-booking'),
                        booking: b,
                        today: today,
                        showStatus: false,
                        onTap: () => context.go('/horarios'),
                      ),
              ),
              const SizedBox(height: 32),
              const SectionLabel('Barbearias'),
              shops.when(
                loading: () => const LoadingBox(),
                error: (e, _) => ErrorBox(
                  error: e,
                  onRetry: () => ref.invalidate(barbershopsProvider),
                ),
                data: (list) => Column(
                  children: [
                    for (final s in list) ...[
                      _ShopTile(shop: s),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterPhoneInfo extends StatelessWidget {
  const _RegisterPhoneInfo({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      key: const ValueKey('home-register-phone'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cadastre seu telefone', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Sem telefone cadastrado. Toque abaixo e digite o seu número.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('home-register-phone-button'),
            onPressed: onTap,
            child: const Text('Cadastrar telefone'),
          ),
        ],
      ),
    );
  }
}

class _EmptyNext extends StatelessWidget {
  const _EmptyNext({required this.firstShopId});

  final String? firstShopId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      key: const ValueKey('home-empty-next'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Você ainda não tem horários', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Escolha uma barbearia e garanta sua cadeira.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: firstShopId == null
                ? null
                : () => context.push('/agendar/$firstShopId'),
            child: const Text('Agendar'),
          ),
        ],
      ),
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop});

  final BarbershopSummary shop;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      onTap: () => context.go('/inicio/barbearia/${shop.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.content_cut, color: t.text),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop.name, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${shop.neighborhood} · ${shop.city}',
                  style: text.bodySmall,
                ),
                if (shop.startingPriceCents != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'A partir de ${formatCents(shop.startingPriceCents!)}',
                    style: text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: t.textMuted),
        ],
      ),
    );
  }
}
