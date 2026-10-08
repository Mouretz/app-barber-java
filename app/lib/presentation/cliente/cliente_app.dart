import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/api_problem.dart';
import '../../core/storage/device_store.dart';
import '../../theme/theme.dart';
import 'cliente_router.dart';

/// App Cliente (flavor `cliente`). Espera ler o que está salvo no aparelho
/// (intro já vista e código do cliente) antes de montar as rotas.
class ClienteApp extends ConsumerStatefulWidget {
  const ClienteApp({super.key, required this.config, this.initialLocation});

  final AppConfig config;

  /// Só para teste: abre direto numa rota.
  final String? initialLocation;

  @override
  ConsumerState<ClienteApp> createState() => _ClienteAppState();
}

class _ClienteAppState extends ConsumerState<ClienteApp> {
  GoRouter? _router;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// Aparelho desconectado pela barbearia (401 com o código salvo), venha de
  /// qual tela vier. Ordem: aviso (uma vez só), introdução e Início de cliente
  /// novo. É um diálogo, e não SnackBar, para o aviso ser lido antes da
  /// introdução tomar a tela.
  Future<void> _showDisconnected() async {
    ref.read(deviceStoreProvider.notifier).ackDisconnectedNotice();
    final router = _router;
    final ctx = router?.routerDelegate.navigatorKey.currentContext;
    if (router == null || ctx == null) return;
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        key: const ValueKey('disconnected-notice'),
        backgroundColor: CortaTokens.of(dctx).surface,
        content: const Text(kDisconnectedMessage),
        actions: [
          TextButton(
            key: const ValueKey('disconnected-ok'),
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    router.go('/intro');
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(deviceStoreProvider.select((s) => s.disconnectedNotice), (
      _,
      show,
    ) {
      if (show) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showDisconnected(),
        );
      }
    });
    final device = ref.watch(deviceStoreProvider);
    if (!device.hydrated) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCortaTheme(),
        home: const Scaffold(),
      );
    }
    _router ??= createClienteRouter(
      introSeen: device.introSeen,
      initialLocation: widget.initialLocation,
    );
    return MaterialApp.router(
      title: widget.config.flavor.appName,
      debugShowCheckedModeBanner: false,
      theme: buildCortaTheme(),
      themeMode: ThemeMode.dark,
      scaffoldMessengerKey: _messenger,
      routerConfig: _router,
    );
  }
}
