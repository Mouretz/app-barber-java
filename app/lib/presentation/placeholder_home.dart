import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../theme/theme.dart';

/// Tela provisória para provar estrutura, flavor e tema no APK.
/// Some quando entrarem as telas do Front-end.
class PlaceholderHome extends StatefulWidget {
  const PlaceholderHome({super.key, required this.config});

  final AppConfig config;

  @override
  State<PlaceholderHome> createState() => _PlaceholderHomeState();
}

class _PlaceholderHomeState extends State<PlaceholderHome> {
  int _tab = 0;

  List<CortaNavItem> get _items => widget.config.flavor == Flavor.cliente
      ? const [
          CortaNavItem(icon: Icons.home_outlined, label: 'Início'),
          CortaNavItem(icon: Icons.event_outlined, label: 'Horários'),
          CortaNavItem(icon: Icons.menu, label: 'Menu'),
        ]
      : const [
          CortaNavItem(icon: Icons.calendar_today_outlined, label: 'Agenda'),
          CortaNavItem(icon: Icons.attach_money, label: 'Caixa'),
          CortaNavItem(icon: Icons.people_outline, label: 'Clientes'),
          CortaNavItem(icon: Icons.menu, label: 'Menu'),
        ];

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BARBEARIA NAVALHA', style: text.labelSmall),
              const SizedBox(height: 6),
              Text(widget.config.flavor.appName, style: text.displaySmall),
              const SizedBox(height: 8),
              Text(
                widget.config.isMock
                    ? 'Modo mock: roda sem servidor.'
                    : 'Modo API: ${widget.config.apiBaseUrl}',
                style: text.bodySmall,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Estrutura e tema prontos. As telas entram nos próximos PRs.',
                    style: text.bodyLarge?.copyWith(color: t.text),
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(onPressed: () {}, child: const Text('Agendar')),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CortaNavBar(
        items: _items,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}
