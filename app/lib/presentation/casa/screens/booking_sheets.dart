import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/format/formatters.dart';
import '../../../core/ids/uuid.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/barbershop.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/staff.dart';
import '../../../theme/theme.dart';
import '../casa_messages.dart';
import '../providers.dart';
import 'agenda_screen.dart';

/// Horário livre: Marcar ou Bloquear (CT-02-05).
Future<void> showFreeSlotActions(
  BuildContext context,
  WidgetRef ref, {
  required ProfessionalPublic professional,
  required DateTime startAt,
  required AgendaQuery query,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${professional.name} · ${hm(spMinuteOfDay(startAt))}',
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('action-book'),
            onPressed: () {
              Navigator.pop(ctx);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => StaffBookingSheet(
                  professional: professional,
                  startAt: startAt,
                  query: query,
                ),
              );
            },
            child: const Text('Marcar'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('action-block'),
            onPressed: () {
              Navigator.pop(ctx);
              showModalBottomSheet<void>(
                context: context,
                builder: (_) => BlockSheet(
                  professional: professional,
                  startAt: startAt,
                  query: query,
                ),
              );
            },
            child: const Text('Bloquear'),
          ),
        ],
      ),
    ),
  );
}

/// Marcado: Concluir, Marcar falta e Cancelar (CT-02-06).
Future<void> showBookingActions(
  BuildContext context,
  WidgetRef ref, {
  required Booking booking,
  required AgendaQuery query,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => StatusSheet(booking: booking, query: query),
  );
}

class StatusSheet extends ConsumerStatefulWidget {
  const StatusSheet({super.key, required this.booking, required this.query});

  final Booking booking;
  final AgendaQuery query;

  @override
  ConsumerState<StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends ConsumerState<StatusSheet> {
  /// Uma chave por status escolhido; tentar de novo usa a mesma.
  final Map<BookingStatus, String> _keys = {};
  bool _busy = false;
  String? _error;

  Future<void> _apply(BookingStatus status) async {
    final s = ref.read(sessionProvider)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(casaApiProvider)
          .changeBookingStatus(
            s.token,
            barbershopId: s.shopId,
            bookingId: widget.booking.id,
            idempotencyKey: _keys.putIfAbsent(status, newUuid),
            status: status,
          );
      ref.invalidate(agendaProvider(widget.query));
      if (mounted) Navigator.pop(context);
    } on ApiProblem catch (e) {
      if (!mounted) return;
      if (e.code == ErrorCode.statusChanged) {
        // Recarrega e fecha: o card mostra o status novo, sem ações velhas.
        ref.invalidate(agendaProvider(widget.query));
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text(kStatusChangedMessage)),
        );
        return;
      }
      // CONCURRENT_UPDATE e os outros: fica aqui, com as opções.
      setState(() => _error = casaMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final b = widget.booking;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${b.client.name} · ${hm(spMinuteOfDay(b.startAt))}',
            style: text.titleMedium,
          ),
          Text(
            '${b.service.name} · ${formatCents(b.priceCents)}',
            style: text.bodySmall?.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: 16),
          for (final (status, label) in const [
            (BookingStatus.completed, 'Concluir'),
            (BookingStatus.noShow, 'Marcar falta'),
            (BookingStatus.canceled, 'Cancelar'),
          ]) ...[
            OutlinedButton(
              key: ValueKey('status-${status.wire}'),
              onPressed: _busy ? null : () => _apply(status),
              child: Text(label),
            ),
            const SizedBox(height: 8),
          ],
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('status-error'),
              style: text.bodyMedium?.copyWith(color: t.error),
            ),
        ],
      ),
    );
  }
}

/// Marcar pela Casa ou balcão. Balcão: telefone opcional (CT-06-07).
class StaffBookingSheet extends ConsumerStatefulWidget {
  const StaffBookingSheet({
    super.key,
    required this.professional,
    required this.startAt,
    required this.query,
  });

  final ProfessionalPublic professional;
  final DateTime startAt;
  final AgendaQuery query;

  @override
  ConsumerState<StaffBookingSheet> createState() => _StaffBookingSheetState();
}

class _StaffBookingSheetState extends ConsumerState<StaffBookingSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _serviceId;
  bool _counter = true;
  bool _busy = false;
  String? _error;

  /// Mesma chave enquanto a folha está aberta: tentar de novo depois de
  /// `CONCURRENT_UPDATE` não duplica a marcação.
  final String _key = newUuid();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = ref.read(sessionProvider)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(casaApiProvider)
          .createStaffBooking(
            s.token,
            barbershopId: s.shopId,
            idempotencyKey: _key,
            request: StaffBookingRequest(
              serviceId: _serviceId!,
              professionalId: widget.professional.id,
              startAt: widget.startAt,
              source: _counter ? BookingSource.counter : BookingSource.staff,
              newClientName: _name.text,
              newClientPhone: _phone.text.trim().isEmpty ? null : _phone.text,
            ),
          );
      ref.invalidate(agendaProvider(widget.query));
      if (mounted) Navigator.pop(context);
    } on ApiProblem catch (e) {
      if (mounted) setState(() => _error = casaMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final services =
        ref.watch(activeServicesProvider).valueOrNull ?? const <Service>[];
    _serviceId ??= services.isEmpty ? null : services.first.id;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marcar · ${widget.professional.name} · ${hm(spMinuteOfDay(widget.startAt))}',
              style: text.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('source-counter'),
                  label: const Text('Balcão'),
                  selected: _counter,
                  onSelected: (_) => setState(() => _counter = true),
                ),
                ChoiceChip(
                  key: const ValueKey('source-staff'),
                  label: const Text('Marcação'),
                  selected: !_counter,
                  onSelected: (_) => setState(() => _counter = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final x in services)
                  ChoiceChip(
                    key: ValueKey('svc-${x.id}'),
                    label: Text(x.name),
                    selected: x.id == _serviceId,
                    onSelected: (_) => setState(() => _serviceId = x.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('book-name'),
              controller: _name,
              decoration: const InputDecoration(hintText: 'Nome do cliente'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('book-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: _counter ? 'Telefone (opcional)' : 'Telefone',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('book-error'),
                style: text.bodyMedium?.copyWith(color: t.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('book-submit'),
              onPressed: _busy || _serviceId == null ? null : _submit,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloquear a partir do horário tocado, até um fim na grade (até 00:00).
class BlockSheet extends ConsumerStatefulWidget {
  const BlockSheet({
    super.key,
    required this.professional,
    required this.startAt,
    required this.query,
  });

  final ProfessionalPublic professional;
  final DateTime startAt;
  final AgendaQuery query;

  @override
  ConsumerState<BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends ConsumerState<BlockSheet> {
  int _minutes = 30;
  String? _error;

  Future<void> _submit() async {
    final s = ref.read(sessionProvider)!;
    try {
      await ref
          .read(casaApiProvider)
          .createBlock(
            s.token,
            barbershopId: s.shopId,
            professionalId: widget.professional.id,
            startAt: widget.startAt,
            endAt: widget.startAt.add(Duration(minutes: _minutes)),
          );
      ref.invalidate(agendaProvider(widget.query));
      if (mounted) Navigator.pop(context);
    } on ApiProblem catch (e) {
      if (mounted) setState(() => _error = casaMessageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final start = spMinuteOfDay(widget.startAt);
    final options = [for (var m = 30; start + m <= 24 * 60; m += 30) m];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bloquear · ${widget.professional.name}',
            style: text.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButton<int>(
            key: const ValueKey('block-end'),
            value: _minutes,
            dropdownColor: t.surface2,
            items: [
              for (final m in options)
                DropdownMenuItem(
                  value: m,
                  child: Text(
                    '${hm(start)} até ${hm((start + m) % (24 * 60))}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _minutes = v ?? 30),
          ),
          if (_error != null)
            Text(_error!, style: text.bodyMedium?.copyWith(color: t.error)),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('block-submit'),
            onPressed: _submit,
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
  }
}
