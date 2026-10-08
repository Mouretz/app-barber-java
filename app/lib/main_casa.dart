import 'app.dart';
import 'core/config/app_config.dart';

/// App Casa (gerente e profissional). Build: `flutter build apk --flavor casa -t lib/main_casa.dart`.
void main() => runCortaAqui(AppConfig.fromEnvironment(Flavor.casa));
