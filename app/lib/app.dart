import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/storage/device_store.dart';
import 'data/mock/mock_seed.dart';
import 'presentation/cliente/cliente_app.dart';
import 'presentation/placeholder_home.dart';
import 'theme/theme.dart';

/// Config do build atual. Os pontos de entrada sobrescrevem este provider.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider sem override'),
);

/// Ponto de partida dos dois apps. Lê a configuração do build e, se ela estiver
/// errada (ex.: `DATA_SOURCE` desconhecido), mostra uma tela de erro em vez de
/// abrir em branco ou cair no mock em silêncio. O Cliente já tem as telas e o
/// go_router dele; a Casa ainda usa a tela provisória.
void bootCortaAqui(Flavor flavor) {
  runApp(rootFor(flavor, () => AppConfig.fromEnvironment(flavor)));
}

/// Widget raiz. Separado do [runApp] para dar para testar a tela de erro.
Widget rootFor(Flavor flavor, AppConfig Function() loadConfig) {
  final AppConfig config;
  try {
    config = loadConfig();
  } on ArgumentError catch (e) {
    return ConfigErrorApp(
      flavor: flavor,
      detail: '${e.name} recebido: "${e.invalidValue}" (${e.message})',
    );
  }
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      ...deviceSeedOverrides(config),
    ],
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
      home: Builder(
        builder: (context) {
          // Cores direto dos tokens do tema escuro: o contexto aqui é o do MaterialApp,
          // mas assim a tela não depende de nenhum provider nem do tema carregar.
          const tokens = CortaTokens.dark;
          final textTheme = Theme.of(context).textTheme;
          return Scaffold(
            backgroundColor: tokens.bg,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Erro de configuração',
                      style: textTheme.headlineSmall?.copyWith(
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Este aplicativo foi gerado com uma configuração inválida '
                      'e não pode abrir. Gere o app de novo com DATA_SOURCE=mock '
                      'ou DATA_SOURCE=api.',
                      style: textTheme.bodyMedium?.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      detail,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// No modo mock, o aparelho que abre o app já vem preso ao João do seed
/// (plano da QA, seção 2, e checklist do APK). No modo api, nada.
List<Override> deviceSeedOverrides(AppConfig config) => [
  if (config.isMock && config.flavor == Flavor.cliente)
    seedSessionProvider.overrideWithValue(MockSeed.joaoSession),
];

class CortaAquiApp extends StatelessWidget {
  const CortaAquiApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    if (config.flavor == Flavor.cliente) return ClienteApp(config: config);
    return MaterialApp(
      title: config.flavor.appName,
      debugShowCheckedModeBanner: false,
      theme: buildCortaTheme(),
      themeMode: ThemeMode.dark,
      home: PlaceholderHome(config: config),
    );
  }
}
