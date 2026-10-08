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
void runCortaAqui(AppConfig config) {
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: CortaAquiApp(config: config),
    ),
  );
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
