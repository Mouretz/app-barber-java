import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../theme/theme.dart';
import 'providers.dart';
import 'screens/agenda_screen.dart';
import 'screens/cash_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/login_screen.dart';
import 'screens/menu_screen.dart';

/// App Casa (flavor `casa`): login de gerente ou profissional e as abas
/// Agenda, Caixa, Clientes e Menu.
class CasaApp extends ConsumerWidget {
  const CasaApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: config.flavor.appName,
      debugShowCheckedModeBanner: false,
      theme: buildCortaTheme(),
      themeMode: ThemeMode.dark,
      home: session == null
          ? LoginScreen(config: config)
          : CasaShell(key: ValueKey(session.token)),
    );
  }
}

class CasaShell extends ConsumerStatefulWidget {
  const CasaShell({super.key});

  @override
  ConsumerState<CasaShell> createState() => _CasaShellState();
}

class _CasaShellState extends ConsumerState<CasaShell> {
  int _tab = 0;

  static const _items = [
    CortaNavItem(icon: Icons.calendar_today_outlined, label: 'Agenda'),
    CortaNavItem(icon: Icons.attach_money, label: 'Caixa'),
    CortaNavItem(icon: Icons.people_outline, label: 'Clientes'),
    CortaNavItem(icon: Icons.menu, label: 'Menu'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [
            AgendaScreen(),
            CashScreen(),
            ClientsScreen(),
            MenuScreen(),
          ],
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
