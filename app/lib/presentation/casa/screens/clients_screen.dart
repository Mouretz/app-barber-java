import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/format/formatters.dart';
import '../../../core/phone/phone.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/staff.dart';
import '../../../theme/theme.dart';
import '../../cliente/widgets/common.dart';
import '../casa_messages.dart';
import '../providers.dart';
import 'agenda_screen.dart';

String phoneLabel(String? phone) =>
    phone == null ? 'Sem telefone' : formatPhone(phone);

/// Clientes (história 17): busca e cadastro (gerente e profissional).
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = CortaTokens.of(context);
    final list = ref.watch(clientSearchProvider(_q));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text('Clientes', style: text.displaySmall),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('client-search'),
          decoration: const InputDecoration(
            hintText: 'Buscar por nome ou telefone',
          ),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('client-new'),
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('Novo cliente'),
          ),
        ),
        list.when(
          loading: () => const LoadingBox(),
          error: (e, _) => Text(
            e is ApiProblem ? casaMessageFor(e) : 'Não deu para carregar.',
            style: text.bodySmall,
          ),
          data: (items) => Column(
            children: [
              for (final c in items)
                SurfaceCard(
                  key: ValueKey('client-${c.id}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ClientDetailScreen(clientId: c.id),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(c.name, style: text.titleSmall)),
                      Text(
                        phoneLabel(c.phone),
                        style: text.bodySmall?.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        String? error;
        return StatefulBuilder(
          builder: (dctx, setLocal) => AlertDialog(
            backgroundColor: CortaTokens.of(dctx).surface,
            title: const Text('Novo cliente'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('new-client-name'),
                  controller: name,
                  decoration: const InputDecoration(hintText: 'Nome'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('new-client-phone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Telefone'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: CortaTokens.of(dctx).error),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Voltar'),
              ),
              TextButton(
                key: const ValueKey('new-client-save'),
                onPressed: () async {
                  final s = ref.read(sessionProvider)!;
                  try {
                    await ref
                        .read(casaApiProvider)
                        .createClient(
                          s.token,
                          barbershopId: s.shopId,
                          name: name.text,
                          phone: phone.text,
                        );
                    ref.invalidate(clientSearchProvider);
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

/// Ficha do cliente. Editar e "Liberar aparelho" só para o gerente; o
/// profissional abre a ficha mas não edita nenhuma.
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final detail = ref.watch(clientDetailProvider(clientId));
    final text = Theme.of(context).textTheme;
    final t = CortaTokens.of(context);
    final today = SpDate.of(ref.watch(clockProvider).now());
    return Scaffold(
      appBar: AppBar(title: const Text('Ficha do cliente')),
      body: detail.when(
        loading: () => const LoadingBox(),
        error: (e, _) => Center(
          child: Text(
            e is ApiProblem ? casaMessageFor(e) : 'Não deu para carregar.',
          ),
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(d.client.name, style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              phoneLabel(d.client.phone),
              key: const ValueKey('client-phone'),
              style: text.bodyMedium?.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: 16),
            if (session?.isManager ?? false) ...[
              OutlinedButton(
                key: const ValueKey('client-edit'),
                onPressed: () => _edit(context, ref, d.client),
                child: const Text('Editar'),
              ),
              if (d.client.hasDevice) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('client-release'),
                  onPressed: () => _release(context, ref),
                  child: const Text('Liberar aparelho'),
                ),
              ],
              const SizedBox(height: 16),
            ],
            const SectionLabel('Últimos horários'),
            for (final b in d.recentBookings)
              SurfaceCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatBookingWhen(b.startAt, today)} · ${b.service.name}',
                        style: text.bodyMedium,
                      ),
                    ),
                    Text(
                      statusLabel(b.status),
                      style: text.bodySmall?.copyWith(
                        color: statusColor(t, b.status),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _release(BuildContext context, WidgetRef ref) async {
    final s = ref.read(sessionProvider)!;
    try {
      await ref
          .read(casaApiProvider)
          .releaseDevice(s.token, barbershopId: s.shopId, clientId: clientId);
      if (context.mounted) {
        showCasaSnack(
          context,
          'Aparelho liberado. O próximo celular que agendar com esse telefone fica preso a ele.',
        );
      }
    } on ApiProblem catch (e) {
      if (context.mounted) showCasaSnack(context, casaMessageFor(e));
    }
    ref.invalidate(clientDetailProvider(clientId));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ClientFile c) async {
    final name = TextEditingController(text: c.name);
    final phone = TextEditingController(
      text: c.phone == null ? '' : formatPhone(c.phone!),
    );
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        String? error;
        return StatefulBuilder(
          builder: (dctx, setLocal) => AlertDialog(
            backgroundColor: CortaTokens.of(dctx).surface,
            title: const Text('Editar cliente'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('edit-client-name'),
                  controller: name,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('edit-client-phone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Telefone'),
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
                key: const ValueKey('edit-client-save'),
                onPressed: () async {
                  final s = ref.read(sessionProvider)!;
                  try {
                    await ref
                        .read(casaApiProvider)
                        .updateClient(
                          s.token,
                          barbershopId: s.shopId,
                          clientId: c.id,
                          name: name.text,
                          phone: phone.text.trim().isEmpty ? null : phone.text,
                        );
                    ref.invalidate(clientDetailProvider(c.id));
                    ref.invalidate(clientSearchProvider);
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
