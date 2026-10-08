import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'presentation/placeholder_home.dart';
import 'theme/theme.dart';

/// Config do build atual. Os pontos de entrada sobrescrevem este provider.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider sem override'),
);

/// Sobe um dos dois apps. Front-end troca o `home` pelo go_router de cada flavor.
/// Ponto de partida dos dois apps. Lê a configuração do build e, se ela estiver
/// errada (ex.: `DATA_SOURCE` desconhecido), mostra uma tela de erro em vez de
/// abrir em branco ou cair no mock em silêncio.
void bootCortaAqui(Flavor flavor) {
  runApp(rootFor(flavor, () => AppConfig.fromEnvironment(flavor)));
}

/// Widget raiz. Separado do [runApp] para dar para testar a tela de erro.
Widget rootFor(Flavor flavor, AppConfig Function() loadConfig) {
  final AppConfig config;
  try {
    config = loadConfig();
  } on ArgumentError catch (e) {
    return ConfigErrorApp(flavor: flavor, detail: '${e.name}: ${e.message}');
  }
  return ProviderScope(
    overrides: [appConfigProvider.overrideWithValue(config)],
    child: CortaAquiApp(config: config),
  );
}

/// Tela curta para build mal configurado. Não usa provider nem dado nenhum.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.flavor, required this.detail});

  final Flavor flavor;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.appName,
      debugShowCheckedModeBanner: false,
      theme: buildCortaTheme(),
      themeMode: ThemeMode.dark,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Erro de configuração',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Este aplicativo foi gerado com uma configuração inválida '
                  'e não pode abrir. Gere o app de novo com DATA_SOURCE=mock '
                  'ou DATA_SOURCE=api.',
                ),
                const SizedBox(height: 12),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CortaAquiApp extends StatelessWidget {
  const CortaAquiApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.flavor.appName,
      debugShowCheckedModeBanner: false,
      theme: buildCortaTheme(),
      themeMode: ThemeMode.dark,
      home: PlaceholderHome(config: config),
    );
  }
}
