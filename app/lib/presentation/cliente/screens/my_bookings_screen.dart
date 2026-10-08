import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/ids/uuid.dart';
import '../../../core/storage/device_store.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/booking.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../domain/scheduling.dart';
import '../../../theme/theme.dart';
import '../providers.dart';
import '../widgets/booking_card.dart';
import '../widgets/common.dart';

/// História 4. Próximos e histórico, com cancelamento até 2h antes.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  BookingScope _scope = BookingScope.upcoming;
  final Set<String> _canceling = {};

  Future<void> _refresh() async {
    ref.invalidate(myBookingsProvider);
    await ref.read(myBookingsProvider(_scope).future);
  }

  Future<void> _cancel(Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CortaTokens.of(ctx).surface,
        title: const Text('Cancelar horário?'),
        content: const Text('O horário volta a ficar livre para outra pessoa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            key: const ValueKey('cancel-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar horário'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final device = ref.read(deviceStoreProvider);
    if (!device.hasSession) return;
    // Uma chave por cancelamento confirmado: repetir o mesmo pedido devolve o
    // mesmo resultado (CT-00-06).
    final key = newUuid();
    setState(() => _canceling.add(b.id));
    String? message = 'Horário cancelado.';
    var statusChanged = false;
    try {
      await ref
          .read(clienteRepositoryProvider)
          .cancelMyBooking(
            clientCode: device.clientCode!,
            bookingId: b.id,
            idempotencyKey: key,
          );
    } on ApiProblem catch (e) {
      // STATUS_CHANGED: avisa e recarrega; a lista mostra o status novo (ex.:
      // "Cancelado pela barbearia") sem o botão (CT-04-10, CT-00-45).
      message = clientMessageFor(e);
      statusChanged = e.code == ErrorCode.statusChanged;
      if (e.code == ErrorCode.unauthorized) {
        // O aviso sai uma vez só, pelo ClienteApp.
        message = null;
        await ref.read(deviceStoreProvider.notifier).disconnectedByShop();
      }
    } catch (_) {
      message = 'Algo deu errado. Tente de novo.';
    }
    if (!mounted) return;
    setState(() => _canceling.remove(b.id));
    ref.invalidate(myBookingsProvider);
    ref.invalidate(availabilityProvider);
    if (statusChanged) {
      // Diz o status novo, que agora está no histórico.
      try {
        final past = await ref.read(
          myBookingsProvider(BookingScope.past).future,
        );
        final now = past.where((x) => x.id == b.id).firstOrNull;
        if (now != null) {
          message =
              'Esse horário mudou para "${bookingStatusLabel(now)}". '
              'A lista foi atualizada.';
        }
      } catch (_) {}
      if (!mounted) return;
    }
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = CortaTokens.of(context);
    final list = ref.watch(myBookingsProvider(_scope));
    final now = ref.watch(clockProvider).now();
    final today = SpDate.of(now);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Text('Meus horários', style: text.displaySmall),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in BookingScope.values)
                    ChoiceChip(
                      key: ValueKey('scope-${s.name}'),
                      label: Text(
                        s == BookingScope.upcoming ? 'Próximos' : 'Histórico',
                        style: TextStyle(
                          color: s == _scope ? t.bg : t.chipInactiveFg,
                          fontWeight: s == _scope
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      selected: s == _scope,
                      onSelected: (_) => setState(() => _scope = s),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              list.when(
                loading: () => const LoadingBox(),
                error: (e, _) => ErrorBox(error: e, onRetry: _refresh),
                data: (items) {
                  if (items.isEmpty) return _Empty(scope: _scope);
                  return Column(
                    children: [
                      for (final b in items) ...[
                        BookingCard(
                          key: ValueKey('booking-${b.id}'),
                          booking: b,
                          today: today,
                          footer: _scope == BookingScope.upcoming
                              ? _CancelFooter(
                                  booking: b,
                                  now: now,
                                  busy: _canceling.contains(b.id),
                                  onCancel: () => _cancel(b),
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão Cancelar só enquanto faltam 2h ou mais. Depois disso some e aparece o
/// aviso (o repositório também recusa).
class _CancelFooter extends StatelessWidget {
  const _CancelFooter({
    required this.booking,
    required this.now,
    required this.busy,
    required this.onCancel,
  });

  final Booking booking;
  final DateTime now;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (booking.status != BookingStatus.scheduled) {
      return const SizedBox.shrink();
    }
    final can = (booking.canCancel ?? true) && clientCanCancel(booking, now);
    if (!can) {
      return Text(
        'Faltam menos de 2 horas: cancelamento só com a barbearia.',
        key: ValueKey('cancel-closed-${booking.id}'),
        style: text.bodySmall,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        key: ValueKey('cancel-${booking.id}'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        onPressed: busy ? null : onCancel,
        child: const Text('Cancelar horário'),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scope});

  final BookingScope scope;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final upcoming = scope == BookingScope.upcoming;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(
            upcoming
                ? 'Você ainda não tem horários'
                : 'Nada no histórico ainda',
            style: text.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            upcoming
                ? 'Escolha uma barbearia no Início para agendar.'
                : 'Os horários que já passaram aparecem aqui.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (upcoming) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/inicio'),
              child: const Text('Ir para o Início'),
            ),
          ],
        ],
      ),
    );
  }
}
