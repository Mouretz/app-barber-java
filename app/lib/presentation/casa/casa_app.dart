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
class CasaApp extends ConsumerStatefulWidget {
  const CasaApp({super.key, required this.config});

  final AppConfig config;

  @override
  ConsumerState<CasaApp> createState() => _CasaAppState();
}

class _CasaAppState extends ConsumerState<CasaApp> {
  final _navigator = GlobalKey<NavigatorState>();

  AppConfig get config => widget.config;

  @override
  Widget build(BuildContext context) {
    // Saiu ou 401 com uma tela aberta por cima (ex.: Equipe): fecha tudo pra
    // a tela de entrar não ficar escondida embaixo.
    ref.listen(sessionProvider, (prev, next) {
      if (prev != null && next == null) {
        _navigator.currentState?.popUntil((r) => r.isFirst);
      }
    });
    final session = ref.watch(sessionProvider);
    final restored = ref.watch(casaSessionRestoredProvider);
    return MaterialApp(
      navigatorKey: _navigator,
      title: config.flavor.appName,
      debugShowCheckedModeBanner: false,
      theme: buildCortaTheme(),
      themeMode: ThemeMode.dark,
      home: session != null
          ? CasaShell(key: ValueKey(session.token))
          : restored
          ? LoginScreen(config: config)
          : const Scaffold(
              key: ValueKey('casa-restoring'),
              body: Center(child: CircularProgressIndicator()),
            ),
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
