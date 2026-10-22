import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/format/formatters.dart';
import '../../../core/ids/uuid.dart';
import '../../../core/phone/phone.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/staff.dart';
import '../../../domain/casa_rules.dart';
import '../../../domain/scheduling.dart';
import '../../../theme/theme.dart';
import '../../cliente/widgets/common.dart';
import '../casa_messages.dart';
import '../providers.dart';
import 'booking_sheets.dart';

String hm(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// Agenda do dia (história 2). Gerente escolhe o profissional (a lista vem da
/// própria agenda, só ativos); profissional vê só a dele, sem seletor.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  SpDate? _date;
  String? _proId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final today = SpDate.of(ref.watch(clockProvider).now());
    final date = _date ?? today;
    final text = Theme.of(context).textTheme;
    final query = (date: date, professionalId: null);
    final agenda = ref.watch(agendaProvider(query));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(agendaProvider(query).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text(
            session.membership.barbershopName.toUpperCase(),
            style: text.labelSmall,
          ),
          const SizedBox(height: 6),
          Text(
            session.isManager ? 'Agenda da casa' : 'Minha agenda',
            key: const ValueKey('agenda-title'),
            style: text.displaySmall,
          ),
          const SizedBox(height: 16),
          _DayStrip(
            today: today,
            selected: date,
            onPick: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 16),
          agenda.when(
            loading: () => const LoadingBox(),
            error: (e, _) => _AgendaError(
              error: e,
              onRetry: () => ref.invalidate(agendaProvider(query)),
            ),
            data: (a) {
              if (a.professionals.isEmpty) {
                return Text(
                  'Nenhum profissional ativo.',
                  style: text.bodyMedium,
                );
              }
              final pro = a.professionals.firstWhere(
                (p) => p.professional.id == _proId,
                orElse: () => a.professionals.first,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session.isManager) ...[
                    _ProPicker(
                      pros: a.professionals,
                      selectedId: pro.professional.id,
                      onPick: (id) => setState(() => _proId = id),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _DayGrid(day: pro, date: date, query: query),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AgendaError extends StatelessWidget {
  const _AgendaError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiProblem
        ? casaMessageFor(error as ApiProblem)
        : 'Não deu para carregar.';
    return Column(
      children: [
        Text(msg, style: Theme.of(context).textTheme.bodySmall),
        TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
      ],
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.today,
    required this.selected,
    required this.onPick,
  });

  final SpDate today;
  final SpDate selected;
  final ValueChanged<SpDate> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < SchedulingRules.horizonDays; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('day-${today.addDays(i).toIso()}'),
                label: Text(formatDayLabel(today.addDays(i), today)),
                selected: today.addDays(i) == selected,
                onSelected: (_) => onPick(today.addDays(i)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProPicker extends StatelessWidget {
  const _ProPicker({
    required this.pros,
    required this.selectedId,
    required this.onPick,
  });

  final List<AgendaProfessional> pros;
  final String selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 16,
      children: [
        for (final p in pros)
          InkWell(
            key: ValueKey('pro-${p.professional.id}'),
            onTap: () => onPick(p.professional.id),
            child: Column(
              children: [
                ProAvatar(
                  name: p.professional.name,
                  selected: p.professional.id == selectedId,
                ),
                const SizedBox(height: 4),
                Text(p.professional.name, style: text.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

/// Grade de 30 em 30 min de 08:00 a 21:00. Fora do expediente fica cinza e
/// sem ações (CT-02-03).
class _DayGrid extends ConsumerWidget {
  const _DayGrid({required this.day, required this.date, required this.query});

  final AgendaProfessional day;
  final SpDate date;
  final AgendaQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[];
    final active = day.bookings.where((b) => b.status.occupiesSlot).toList();
    final inactive = day.bookings.where((b) => !b.status.occupiesSlot).toList();
    for (
      var m = CasaRules.openMinute;
      m < CasaRules.closeMinute;
      m += SchedulingRules.slotMinutes
    ) {
      final at = date.at(m);
      final slot = TimeSpan(at, at.add(const Duration(minutes: 30)));
      final starting = active.where((b) => b.startAt == at).firstOrNull;
      final covered = active.any(
        (b) => b.startAt.isBefore(at) && b.endAt.isAfter(at),
      );
      final block = day.blocks.where((b) => b.span.overlaps(slot)).firstOrNull;
      final inHours = day.workingWindows.any(
        (w) => m >= w.startMinute && m < w.endMinute,
      );
      for (final b in inactive.where((b) => b.startAt == at)) {
        rows.add(_BookingTile(booking: b, day: day, query: query));
      }
      if (starting != null) {
        rows.add(_BookingTile(booking: starting, day: day, query: query));
      } else if (covered) {
        continue;
      } else if (block != null) {
        rows.add(_BlockTile(minute: m, block: block, query: query));
      } else if (!inHours) {
        rows.add(_SlotTile(minute: m, offHours: true));
      } else {
        rows.add(
          _SlotTile(
            minute: m,
            offHours: false,
            onTap: () => showFreeSlotActions(
              context,
              ref,
              professional: day.professional,
              startAt: at,
              query: query,
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.minute, required this.offHours, this.onTap});

  final int minute;
  final bool offHours;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: offHours ? t.slotOffHours : t.slotFree,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('slot-${hm(minute)}'),
          borderRadius: BorderRadius.circular(12),
          onTap: offHours ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    hm(minute),
                    style: text.bodyMedium?.copyWith(color: t.textMuted),
                  ),
                ),
                Text(
                  offHours ? 'Fora do expediente' : 'Livre',
                  style: text.bodyMedium?.copyWith(
                    color: offHours ? t.textMuted : t.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockTile extends ConsumerWidget {
  const _BlockTile({
    required this.minute,
    required this.block,
    required this.query,
  });

  final int minute;
  final Block block;
  final AgendaQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final isStart =
        spMinuteOfDay(block.startAt) == minute ||
        SpDate.of(block.startAt) != SpDate.of(block.endAt) &&
            minute == CasaRules.openMinute;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                hm(minute),
                style: text.bodyMedium?.copyWith(color: t.textMutedOnSurface2),
              ),
            ),
            Expanded(
              child: Text(
                'Bloqueado',
                style: text.bodyMedium?.copyWith(color: t.text),
              ),
            ),
            if (isStart)
              TextButton(
                key: ValueKey('unblock-${hm(minute)}'),
                onPressed: () async {
                  final s = ref.read(sessionProvider)!;
                  try {
                    await ref
                        .read(casaApiProvider)
                        .deleteBlock(
                          s.token,
                          barbershopId: s.shopId,
                          blockId: block.id,
                        );
                  } on ApiProblem catch (e) {
                    if (context.mounted) {
                      showCasaSnack(context, casaMessageFor(e));
                    }
                  }
                  ref.invalidate(agendaProvider(query));
                },
                child: const Text('Desbloquear'),
              ),
          ],
        ),
      ),
    );
  }
}

void showCasaSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Card de um agendamento. Destacado quando bate com bloqueio
/// (`overlapsBlock`) ou ficou fora do expediente (folga ou expediente
/// reduzido depois de marcado, CT-07-03/04).
class _BookingTile extends ConsumerWidget {
  const _BookingTile({
    required this.booking,
    required this.day,
    required this.query,
  });

  final Booking booking;
  final AgendaProfessional day;
  final AgendaQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final b = booking;
    final active = b.status.occupiesSlot;
    final outside =
        active &&
        !fitsWorkingHours(
          b.startAt,
          b.endAt.difference(b.startAt).inMinutes,
          day.workingWindows,
        );
    final overlaps = b.overlapsBlock == true;
    final flagged = overlaps || outside;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: flagged
              ? BorderSide(color: t.error, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          key: ValueKey('booking-${b.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: b.status == BookingStatus.scheduled
              ? () => showBookingActions(context, ref, booking: b, query: query)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        hm(spMinuteOfDay(b.startAt)),
                        style: text.bodyMedium?.copyWith(color: t.textMuted),
                      ),
                    ),
                    Expanded(
                      child: Text(b.client.name, style: text.titleSmall),
                    ),
                    Text(
                      statusLabel(b.status),
                      style: text.bodySmall?.copyWith(
                        color: statusColor(t, b.status),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Text(
                    '${b.service.name} · '
                    '${b.client.phone == null ? 'Sem telefone' : formatPhone(b.client.phone!)}',
                    style: text.bodySmall?.copyWith(color: t.textMuted),
                  ),
                ),
                if (overlaps)
                  _Flag(
                    key: ValueKey('overlap-${b.id}'),
                    text: 'Bate com um bloqueio',
                  ),
                if (outside)
                  _Flag(
                    key: ValueKey('outside-${b.id}'),
                    text: 'Fora do expediente',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: t.error),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.text),
          ),
        ],
      ),
    );
  }
}

String statusLabel(BookingStatus s) => switch (s) {
  BookingStatus.scheduled => 'Agendado',
  BookingStatus.completed => 'Concluído',
  BookingStatus.noShow => 'Falta',
  BookingStatus.canceled => 'Cancelado',
};

Color statusColor(CortaTokens t, BookingStatus s) => switch (s) {
  BookingStatus.scheduled => t.statusScheduled,
  BookingStatus.completed => t.statusCompleted,
  BookingStatus.noShow => t.statusNoShow,
  BookingStatus.canceled => t.statusCanceled,
};

/// Uma chave por tentativa de ação; repetir depois de `CONCURRENT_UPDATE`
/// usa a mesma.
String newIdempotencyKey() => newUuid();
