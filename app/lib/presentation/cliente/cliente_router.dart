import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'cliente_shell.dart';
import 'screens/barbershop_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/my_bookings_screen.dart';

/// Rotas do app Cliente.
///
/// - `/intro`: introdução (história 14), na primeira abertura e sempre que o
///   app volta a ser novo ("Entrar como cliente novo" e aparelho desconectado).
/// - `/inicio` e `/inicio/barbearia/:id` (histórias 15 e 16).
/// - `/agendar/:barbershopId?servico=&profissional=` em tela cheia (história 1).
/// - `/horarios` (história 4) e `/menu`.
GoRouter createClienteRouter({
  required bool introSeen,
  String? initialLocation,
}) {
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation ?? (introSeen ? '/inicio' : '/intro'),
    routes: [
      GoRoute(path: '/intro', builder: (_, _) => const IntroScreen()),
      GoRoute(
        path: '/agendar/:barbershopId',
        parentNavigatorKey: rootKey,
        builder: (_, state) => BookingScreen(
          barbershopId: state.pathParameters['barbershopId']!,
          initialServiceId: state.uri.queryParameters['servico'],
          initialProfessionalId: state.uri.queryParameters['profissional'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ClienteShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inicio',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'barbearia/:id',
                    builder: (_, state) => BarbershopScreen(
                      barbershopId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/horarios',
                builder: (_, _) => const MyBookingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/menu', builder: (_, _) => const MenuScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
