import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/api_problem.dart';
import '../../../theme/theme.dart';
import '../casa_messages.dart';
import '../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.config});

  final AppConfig config;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(casaNoticeProvider, (_, next) {
      if (next != null) _showNotice(next);
    }, fireImmediately: true);
  }

  void _showNotice(String msg) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(casaNoticeProvider.notifier).state = null;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('casa-notice'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(_email.text, _password.text);
    } on ApiProblem catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.code == ErrorCode.unauthorized
            ? kLoginFailedMessage
            : casaMessageFor(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final hint = ref.watch(casaLoginHintProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          children: [
            Text('CORTAAQUI CASA', style: text.labelSmall),
            const SizedBox(height: 6),
            Text('Entrar', style: text.displaySmall),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('login-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'E-mail'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('login-password'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Senha'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: text.bodyMedium?.copyWith(color: t.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('login-submit'),
              onPressed: _busy ? null : _submit,
              child: const Text('Entrar'),
            ),
            if (hint != null) ...[
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modo mock: logins de teste',
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final l in hint.logins)
                        Text(
                          '${l.$1}: ${l.$2}',
                          style: text.bodySmall?.copyWith(color: t.textMuted),
                        ),
                      Text(
                        'Senha: ${hint.password}',
                        style: text.bodySmall?.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
