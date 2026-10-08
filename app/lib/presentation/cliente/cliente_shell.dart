import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';

/// Menu de baixo do app Cliente: Início | Horários | Menu.
class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const items = [
    CortaNavItem(icon: Icons.home_outlined, label: 'Início'),
    CortaNavItem(icon: Icons.event_outlined, label: 'Horários'),
    CortaNavItem(icon: Icons.menu, label: 'Menu'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: CortaNavBar(
        items: items,
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
