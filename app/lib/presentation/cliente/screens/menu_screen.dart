import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app.dart';
import '../../../core/storage/device_store.dart';
import '../../../theme/theme.dart';
import '../widgets/common.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(appConfigProvider);
    final hasCode = ref.watch(deviceStoreProvider).clientCode != null;
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
                      hasCode
                          ? 'Seus dados ficam salvos aqui para os próximos agendamentos.'
                          : 'Seu primeiro agendamento salva seus dados neste aparelho.',
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
