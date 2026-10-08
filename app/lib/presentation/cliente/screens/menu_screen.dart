import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app.dart';
import '../../../core/phone/phone.dart';
import '../../../core/storage/device_store.dart';
import '../../../theme/theme.dart';
import '../widgets/common.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  /// Só no modo mock: o aparelho esquece o cliente e volta ao Início. O
  /// "servidor" do mock não muda: o telefone que estava preso a este aparelho
  /// continua preso ao código antigo, como se fosse outro celular.
  Future<void> _newClient(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CortaTokens.of(ctx).surface,
        title: const Text('Entrar como cliente novo?'),
        content: const Text(
          'Este aparelho esquece o telefone salvo e fica como um celular limpo. '
          'Os horários continuam na barbearia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            key: const ValueKey('new-client-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entrar como cliente novo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(deviceStoreProvider.notifier).forgetClient();
    if (!context.mounted) return;
    // O app volta a ser novo: introdução e depois o Início vazio.
    context.go('/intro');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(appConfigProvider);
    final device = ref.watch(deviceStoreProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text('Menu', style: text.displaySmall),
            const SizedBox(height: 24),
            const SectionLabel('Este aparelho'),
            SurfaceCard(
              child: Row(
                children: [
                  Icon(Icons.phone_iphone, color: t.text),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      device.hasSession
                          ? 'Este aparelho está ligado ao telefone '
                                '${formatPhone(device.boundPhone!)}.'
                          : 'Seu primeiro agendamento liga este aparelho ao seu '
                                'telefone.',
                      key: const ValueKey('menu-device'),
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('App'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.auto_stories_outlined, color: t.text),
                    title: Text('Ver a introdução', style: text.bodyLarge),
                    trailing: Icon(Icons.chevron_right, color: t.textMuted),
                    onTap: () => context.go('/intro'),
                  ),
                  // Só no modo mock (AppConfig.isMock). Ligado ao servidor, o
                  // botão não existe: a troca de celular é com a barbearia.
                  if (config.isMock) ...[
                    Divider(color: t.border, indent: 16),
                    ListTile(
                      key: const ValueKey('menu-new-client'),
                      leading: Icon(Icons.person_add_alt, color: t.text),
                      title: Text(
                        'Entrar como cliente novo',
                        style: text.bodyLarge,
                      ),
                      subtitle: Text(
                        'Só no modo mock. Apaga o telefone salvo neste aparelho.',
                        style: text.bodySmall,
                      ),
                      onTap: () => _newClient(context, ref),
                    ),
                  ],
                  Divider(color: t.border, indent: 16),
                  ListTile(
                    leading: Icon(Icons.info_outline, color: t.text),
                    title: Text(config.flavor.appName, style: text.bodyLarge),
                    subtitle: Text(
                      config.isMock
                          ? 'Modo mock: roda sem servidor.'
                          : 'Modo API: ${config.apiBaseUrl}',
                      style: text.bodySmall,
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
}
