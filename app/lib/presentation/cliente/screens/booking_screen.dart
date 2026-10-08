import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/barbershop.dart';
import '../../../data/models/booking.dart';
import '../../../domain/scheduling.dart';
import '../../../theme/theme.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'confirm_booking_sheet.dart';

/// História 1. Serviço, profissional, dia (14 dias), turno e horário exato.
///
/// A tela não calcula horário livre: mostra a lista que o repositório devolve,
/// só separada por turno (CT-01-25).
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({
    super.key,
    required this.barbershopId,
    this.initialServiceId,
    this.initialProfessionalId,
  });

  final String barbershopId;
  final String? initialServiceId;
  final String? initialProfessionalId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String? _serviceId;
  String? _proId;
  late SpDate _date;
  Period? _period; // null = primeiro turno com horário
  DateTime? _slot;
  Booking? _booked;

  @override
  void initState() {
    super.initState();
    _serviceId = widget.initialServiceId;
    _proId = widget.initialProfessionalId;
    _date = SpDate.of(ref.read(clockProvider).now());
  }

  AvailabilityQuery? get _query => (_serviceId == null || _proId == null)
      ? null
      : (
          barbershopId: widget.barbershopId,
          serviceId: _serviceId!,
          professionalId: _proId!,
          date: _date,
        );

  void _resetSlot() {
    _slot = null;
    _period = null;
  }

  Future<void> _continue(BarbershopDetail shop) async {
    final service = shop.services.firstWhere((s) => s.id == _serviceId);
    final pro = shop.professionals.firstWhere((p) => p.id == _proId);
    final query = _query!;
    final result = await showModalBottomSheet<ConfirmResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConfirmBookingSheet(
        shop: shop,
        service: service,
        professional: pro,
        startAt: _slot!,
      ),
    );
    if (!mounted || result == null) return;
    ref.invalidate(myBookingsProvider);
    ref.invalidate(availabilityProvider(query));
    if (result.booking != null) {
      setState(() => _booked = result.booking);
    } else if (result.slotLostMessage != null) {
      setState(() => _slot = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.slotLostMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopAsync = ref.watch(barbershopProvider(widget.barbershopId));
    if (_booked != null) {
      return _BookedView(booking: _booked!);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Agendar')),
      body: shopAsync.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(
          error: e,
          onRetry: () =>
              ref.invalidate(barbershopProvider(widget.barbershopId)),
        ),
        data: _buildForm,
      ),
      bottomNavigationBar: shopAsync.hasValue
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                key: const ValueKey('booking-continue'),
                onPressed: _canContinue
                    ? () => _continue(shopAsync.requireValue)
                    : null,
                child: const Text('Continuar'),
              ),
            )
          : null,
    );
  }

  /// Só chamado dentro do `build` (usa `ref.watch`).
  bool get _canContinue {
    final q = _query;
    if (q == null || _slot == null) return false;
    final slots = ref.watch(availabilityProvider(q)).valueOrNull?.slots;
    return slots != null && slots.any((s) => s.startAt == _slot);
  }

  Widget _buildForm(BarbershopDetail shop) {
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).now();
    final today = SpDate.of(now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(shop.name, style: text.bodySmall),
        const SizedBox(height: 24),
        const SectionLabel('Serviço'),
        for (final s in shop.services) ...[
          _ServiceOption(
            service: s,
            selected: s.id == _serviceId,
            onTap: () => setState(() {
              _serviceId = s.id;
              _resetSlot();
            }),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 20),
        const SectionLabel('Profissional'),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in shop.professionals)
                _ProOption(
                  pro: p,
                  selected: p.id == _proId,
                  onTap: () => setState(() {
                    _proId = p.id;
                    _resetSlot();
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Dia'),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: SchedulingRules.horizonDays,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = bookableDays(now)[i];
              return _DayOption(
                date: d,
                today: today,
                selected: d == _date,
                onTap: () => setState(() {
                  _date = d;
                  _resetSlot();
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Horário'),
        _buildSlots(),
      ],
    );
  }

  Widget _buildSlots() {
    final text = Theme.of(context).textTheme;
    final q = _query;
    if (q == null) {
      return Text(
        'Escolha o serviço e o profissional para ver os horários livres.',
        style: text.bodySmall,
      );
    }
    final av = ref.watch(availabilityProvider(q));
    return av.when(
      loading: () => const LoadingBox(height: 100),
      error: (e, _) => ErrorBox(
        error: e,
        onRetry: () => ref.invalidate(availabilityProvider(q)),
      ),
      data: (a) {
        if (a.slots.isEmpty) {
          return Text(
            'Sem horários livres nesse dia. Tente outro dia ou profissional.',
            key: const ValueKey('slots-empty-day'),
            style: text.bodySmall,
          );
        }
        final period =
            _period ??
            Period.values.firstWhere((p) => a.inPeriod(p).isNotEmpty);
        final slots = a.inPeriod(period);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final p in Period.values)
                  _Chip(
                    key: ValueKey('period-${p.wire}'),
                    label: p.label,
                    selected: p == period,
                    onTap: () => setState(() => _period = p),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (slots.isEmpty)
              Text(
                'Sem horários livres nesse turno.',
                key: const ValueKey('slots-empty-period'),
                style: text.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in slots)
                    _Chip(
                      key: ValueKey('slot-${formatHm(s.startAt)}'),
                      label: formatHm(s.startAt),
                      selected: s.startAt == _slot,
                      onTap: () => setState(() => _slot = s.startAt),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Chip de turno e de horário: o escolhido fica branco (não amarelo).
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? t.bg : t.chipInactiveFg,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _ServiceOption extends StatelessWidget {
  const _ServiceOption({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final Service service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      key: ValueKey('service-${service.id}'),
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? t.text : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      formatDuration(service.durationMinutes),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(formatCents(service.priceCents), style: text.titleMedium),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? t.text : t.navInactive,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profissional escolhido fica amarelo (anel e nome).
class _ProOption extends StatelessWidget {
  const _ProOption({
    required this.pro,
    required this.selected,
    required this.onTap,
  });

  final ProfessionalPublic pro;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: ValueKey('pro-${pro.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            children: [
              ProAvatar(name: pro.name, size: 62, selected: selected),
              const SizedBox(height: 6),
              Text(
                pro.name,
                key: ValueKey('pro-name-${pro.id}'),
                style: TextStyle(
                  color: selected ? t.accent : t.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayOption extends StatelessWidget {
  const _DayOption({
    required this.date,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final SpDate date;
  final SpDate today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final fg = selected ? t.bg : t.text;
    final top = date == today ? 'hoje' : weekdayShort(date);
    return InkWell(
      key: ValueKey('day-${date.toIso()}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 56,
        decoration: BoxDecoration(
          color: selected ? t.text : t.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              top,
              style: TextStyle(
                color: selected ? t.bg : t.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: TextStyle(
                color: fg,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tela de sucesso depois de confirmar.
class _BookedView extends ConsumerWidget {
  const _BookedView({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final today = SpDate.of(ref.watch(clockProvider).now());
    return Scaffold(
      key: const ValueKey('booking-success'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, color: t.text, size: 56),
              const SizedBox(height: 20),
              Text('Horário marcado', style: text.displaySmall),
              const SizedBox(height: 12),
              Text(
                formatBookingWhen(booking.startAt, today),
                style: text.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${booking.service.name} com ${booking.professional.name}'
                '${booking.barbershopName == null ? '' : ' · ${booking.barbershopName}'}',
                style: text.bodyLarge?.copyWith(color: t.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                'Dá para cancelar até 2 horas antes, em Horários.',
                style: text.bodySmall,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go('/horarios'),
                child: const Text('Ver meus horários'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.go('/inicio'),
                  child: const Text('Voltar ao início'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
