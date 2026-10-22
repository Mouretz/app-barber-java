import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/format/formatters.dart';
import '../../../data/models/barbershop.dart';
import '../../../data/models/staff.dart';
import '../../../domain/casa_rules.dart';
import '../../../domain/scheduling.dart';
import '../../../theme/theme.dart';
import '../../cliente/widgets/common.dart';
import '../casa_messages.dart';
import '../providers.dart';
import 'agenda_screen.dart';

/// Menu. Gerência (equipe, serviços, expediente e %) só aparece pro gerente.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider)!;
    final text = Theme.of(context).textTheme;
    final t = CortaTokens.of(context);
    final roles = [
      if (s.isManager) 'Gerente',
      if (s.ownProfessionalId != null) 'Profissional',
    ].join(' e ');
    void open(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text('Menu', style: text.displaySmall),
        const SizedBox(height: 8),
        Text(s.user.name, style: text.titleMedium),
        Text(
          '$roles · ${s.membership.barbershopName}',
          key: const ValueKey('menu-roles'),
          style: text.bodySmall?.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: 20),
        if (s.isManager) ...[
          const SectionLabel('Gerência'),
          _Item(
            key: const ValueKey('menu-team'),
            label: 'Equipe',
            onTap: () => open(const TeamScreen()),
          ),
          _Item(
            key: const ValueKey('menu-services'),
            label: 'Serviços e preços',
            onTap: () => open(const ServicesScreen()),
          ),
          _Item(
            key: const ValueKey('menu-hours'),
            label: 'Expediente',
            onTap: () => open(const HoursScreen()),
          ),
          _Item(
            key: const ValueKey('menu-commission'),
            label: 'Divisão (%)',
            onTap: () => open(const CommissionScreen()),
          ),
          const SizedBox(height: 20),
        ],
        _Item(
          key: const ValueKey('menu-logout'),
          label: 'Sair',
          onTap: () => ref.read(sessionProvider.notifier).logout(),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Equipe (história 10): lista de gestão com inativos; ativar e desativar.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(professionalsProvider);
    final t = CortaTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Equipe')),
      body: list.when(
        loading: () => const LoadingBox(),
        error: (e, _) => Center(
          child: Text(
            e is ApiProblem ? casaMessageFor(e) : 'Não deu para carregar.',
          ),
        ),
        data: (pros) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final p in pros)
              SurfaceCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            p.active ? 'Ativo' : 'Desativado',
                            key: ValueKey('team-status-${p.id}'),
                            style: TextStyle(color: t.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      key: ValueKey('team-active-${p.id}'),
                      value: p.active,
                      onChanged: (v) async {
                        final s = ref.read(sessionProvider)!;
                        try {
                          await ref
                              .read(casaApiProvider)
                              .updateProfessional(
                                s.token,
                                barbershopId: s.shopId,
                                professionalId: p.id,
                                active: v,
                              );
                        } on ApiProblem catch (e) {
                          if (context.mounted) {
                            showCasaSnack(context, casaMessageFor(e));
                          }
                        }
                        ref.invalidate(professionalsProvider);
                        ref.invalidate(agendaProvider);
                        // O próprio papel pode ter mudado (gerente desativado
                        // como profissional fica sem agenda própria).
                        await ref.read(sessionProvider.notifier).refresh();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final _servicesProvider = FutureProvider.autoDispose<List<Service>>((ref) {
  final s = ref.watch(sessionProvider)!;
  return ref
      .watch(casaApiProvider)
      .listServices(s.token, barbershopId: s.shopId);
});

/// Serviços e preços (história 10). Duração de 30 a 480 min, de 30 em 30.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_servicesProvider);
    final t = CortaTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Serviços e preços')),
      body: list.when(
        loading: () => const LoadingBox(),
        error: (e, _) => Center(
          child: Text(
            e is ApiProblem ? casaMessageFor(e) : 'Não deu para carregar.',
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final x in items)
              SurfaceCard(
                key: ValueKey('service-${x.id}'),
                onTap: () => _edit(context, ref, x),
                child: Row(
                  children: [
                    Expanded(child: Text(x.name)),
                    Text(
                      '${formatDuration(x.durationMinutes)} · ${formatCents(x.priceCents)}',
                      style: TextStyle(color: t.textMuted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Service x) async {
    var duration = x.durationMinutes;
    final price = TextEditingController(
      text: (x.priceCents / 100).toStringAsFixed(2),
    );
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        String? error;
        return StatefulBuilder(
          builder: (dctx, setLocal) => AlertDialog(
            backgroundColor: CortaTokens.of(dctx).surface,
            title: Text(x.name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<int>(
                  key: const ValueKey('service-duration'),
                  value: duration,
                  dropdownColor: CortaTokens.of(dctx).surface2,
                  items: [
                    for (
                      var m = CasaRules.minServiceMinutes;
                      m <= CasaRules.maxServiceMinutes;
                      m += SchedulingRules.slotMinutes
                    )
                      DropdownMenuItem(
                        value: m,
                        child: Text(formatDuration(m)),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => duration = v ?? duration),
                ),
                TextField(
                  key: const ValueKey('service-price'),
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: 'Preço (R\$)'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: CortaTokens.of(dctx).error),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Voltar'),
              ),
              TextButton(
                key: const ValueKey('service-save'),
                onPressed: () async {
                  final cents =
                      ((double.tryParse(price.text.replaceAll(',', '.')) ??
                                  -1) *
                              100)
                          .round();
                  final s = ref.read(sessionProvider)!;
                  try {
                    await ref
                        .read(casaApiProvider)
                        .updateService(
                          s.token,
                          barbershopId: s.shopId,
                          serviceId: x.id,
                          patch: ServicePatch(
                            durationMinutes: duration,
                            priceCents: cents,
                          ),
                        );
                    ref.invalidate(_servicesProvider);
                    ref.invalidate(activeServicesProvider);
                    if (dctx.mounted) Navigator.pop(dctx);
                  } on ApiProblem catch (e) {
                    setLocal(() => error = casaMessageFor(e));
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          ),
        );
      },
    );
  }
}

const _weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// Expediente (história 7): uma janela por dia, de 08:00 a 21:00 na grade de
/// 30 min. Dia desligado é folga fixa.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  String? _proId;
  Map<int, List<WorkWindow>>? _days;
  String? _message;

  Future<void> _load(String proId) async {
    final s = ref.read(sessionProvider)!;
    final d = await ref
        .read(casaApiProvider)
        .getWorkingHours(
          s.token,
          barbershopId: s.shopId,
          professionalId: proId,
        );
    setState(() {
      _proId = proId;
      _days = {
        for (final e in d.entries) e.key: [...e.value],
      };
      _message = null;
    });
  }

  Future<void> _save() async {
    final s = ref.read(sessionProvider)!;
    for (final e in _days!.entries) {
      final p = checkDayWindows(e.value);
      if (p != null) {
        setState(() => _message = casaMessageFor(p));
        return;
      }
    }
    try {
      await ref
          .read(casaApiProvider)
          .replaceWorkingHours(
            s.token,
            barbershopId: s.shopId,
            professionalId: _proId!,
            days: _days!,
          );
      ref.invalidate(agendaProvider);
      setState(() => _message = 'Expediente salvo.');
    } on ApiProblem catch (e) {
      setState(() => _message = casaMessageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pros = ref.watch(professionalsProvider).valueOrNull ?? const [];
    final text = Theme.of(context).textTheme;
    final hours = [
      for (var m = CasaRules.openMinute; m <= CasaRules.closeMinute; m += 30) m,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Expediente')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final p in pros.where((p) => p.active))
                ChoiceChip(
                  key: ValueKey('hours-pro-${p.id}'),
                  label: Text(p.name),
                  selected: p.id == _proId,
                  onSelected: (_) => _load(p.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_days != null)
            for (var d = 1; d <= 7; d++)
              Row(
                children: [
                  SizedBox(width: 44, child: Text(_weekdays[d - 1])),
                  Switch(
                    value: _days!.containsKey(d),
                    onChanged: (on) => setState(() {
                      if (on) {
                        _days![d] = [WorkWindow.hm('09:00', '18:00')];
                      } else {
                        _days!.remove(d);
                      }
                    }),
                  ),
                  if (_days!.containsKey(d)) ...[
                    DropdownButton<int>(
                      key: ValueKey('hours-start-$d'),
                      value: _days![d]!.first.startMinute,
                      items: [
                        for (final m in hours.take(hours.length - 1))
                          DropdownMenuItem(value: m, child: Text(hm(m))),
                      ],
                      onChanged: (v) => setState(() {
                        final w = _days![d]!.first;
                        if (v != null && v < w.endMinute) {
                          _days![d] = [WorkWindow(v, w.endMinute)];
                        }
                      }),
                    ),
                    const Text(' até '),
                    DropdownButton<int>(
                      key: ValueKey('hours-end-$d'),
                      value: _days![d]!.last.endMinute,
                      items: [
                        for (final m in hours.skip(1))
                          DropdownMenuItem(value: m, child: Text(hm(m))),
                      ],
                      onChanged: (v) => setState(() {
                        final w = _days![d]!.first;
                        if (v != null && v > w.startMinute) {
                          _days![d] = [WorkWindow(w.startMinute, v)];
                        }
                      }),
                    ),
                  ],
                ],
              ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, style: text.bodyMedium),
            ),
          const SizedBox(height: 16),
          if (_days != null)
            FilledButton(
              key: const ValueKey('hours-save'),
              onPressed: _save,
              child: const Text('Salvar'),
            ),
        ],
      ),
    );
  }
}

/// Divisão (história 20): padrão da casa e % própria por profissional.
class CommissionScreen extends ConsumerStatefulWidget {
  const CommissionScreen({super.key});

  @override
  ConsumerState<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends ConsumerState<CommissionScreen> {
  CommissionSettings? _settings;
  final Map<String, TextEditingController> _pro = {};
  final _default = TextEditingController();
  String? _message;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final s = ref.read(sessionProvider)!;
      try {
        final c = await ref
            .read(casaApiProvider)
            .getCommission(s.token, barbershopId: s.shopId);
        setState(() {
          _settings = c;
          _default.text = '${c.standard.professionalPercent}';
          for (final e in c.professionals.entries) {
            _pro[e.key] = TextEditingController(
              text: '${e.value.professionalPercent}',
            );
          }
        });
      } on ApiProblem catch (e) {
        setState(() => _message = casaMessageFor(e));
      }
    });
  }

  @override
  void dispose() {
    _default.dispose();
    for (final c in _pro.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Só inteiro de 0 a 100 (decimal e texto são recusados, CT-20-03).
  int? _parse(String raw) =>
      RegExp(r'^\d{1,3}$').hasMatch(raw.trim()) ? int.parse(raw.trim()) : null;

  Future<void> _save() async {
    final std = _parse(_default.text);
    final map = <String, CommissionSplit>{};
    var ok = std != null && std <= 100;
    for (final e in _pro.entries) {
      if (e.value.text.trim().isEmpty) continue;
      final v = _parse(e.value.text);
      if (v == null || v > 100) ok = false;
      if (v != null) {
        map[e.key] = CommissionSplit(
          shopPercent: 100 - v,
          professionalPercent: v,
        );
      }
    }
    if (!ok) {
      setState(() => _message = 'Use números inteiros de 0 a 100.');
      return;
    }
    final s = ref.read(sessionProvider)!;
    try {
      await ref
          .read(casaApiProvider)
          .replaceCommission(
            s.token,
            barbershopId: s.shopId,
            settings: CommissionSettings(
              standard: CommissionSplit(
                shopPercent: 100 - std!,
                professionalPercent: std,
              ),
              professionals: map,
            ),
          );
      setState(
        () => _message =
            'Divisão salva. Vale para o que for concluído daqui pra frente.',
      );
    } on ApiProblem catch (e) {
      setState(() => _message = casaMessageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pros = ref.watch(professionalsProvider).valueOrNull ?? const [];
    final t = CortaTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Divisão (%)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_settings != null) ...[
            Text(
              '% do profissional (o resto fica com a casa)',
              style: TextStyle(color: t.textMuted),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('commission-default'),
              controller: _default,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Padrão da casa'),
            ),
            const SizedBox(height: 16),
            for (final p in pros)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: ValueKey('commission-${p.id}'),
                  controller: _pro.putIfAbsent(p.id, TextEditingController.new),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '${p.name}: usa o padrão',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('commission-save'),
              onPressed: _save,
              child: const Text('Salvar'),
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, key: const ValueKey('commission-message')),
            ),
        ],
      ),
    );
  }
}
