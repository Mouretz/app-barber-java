import 'app.dart';
import 'core/config/app_config.dart';

/// App Cliente. Build: `flutter build apk --flavor cliente -t lib/main_cliente.dart`.
void main() => runCortaAqui(AppConfig.fromEnvironment(Flavor.cliente));
