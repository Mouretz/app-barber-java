import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/device_store.dart';
import '../../../theme/theme.dart';

class _IntroPage {
  const _IntroPage(this.icon, this.label, this.title, this.body);

  final IconData icon;
  final String label;
  final String title;
  final String body;
}

const _pages = [
  _IntroPage(
    Icons.content_cut,
    'Agendamento',
    'Sem fila e sem ligação',
    'Escolha a barbearia, o serviço e o horário. A cadeira fica no seu nome.',
  ),
  _IntroPage(
    Icons.person_outline,
    'Profissional',
    'Corte com quem você confia',
    'Veja quem atende em cada barbearia e escolha o seu profissional.',
  ),
  _IntroPage(
    Icons.event_available_outlined,
    'Seus horários',
    'Tudo na palma da mão',
    'Acompanhe os próximos horários e cancele até 2 horas antes.',
  ),
];

/// História 14. Três telas, "Pular" e "Próximo". Rótulo e "Próximo" em branco;
/// só o ponto ativo fica amarelo.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _ctrl = PageController();
  int _page = 0;

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(deviceStoreProvider.notifier).markIntroSeen();
    if (mounted) context.go('/inicio');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: t.surface,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Icon(p.icon, size: 96, color: t.text),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          p.label.toUpperCase(),
                          key: ValueKey('intro-label-$i'),
                          style: text.labelSmall?.copyWith(color: t.text),
                        ),
                        const SizedBox(height: 8),
                        Text(p.title, style: text.displaySmall),
                        const SizedBox(height: 12),
                        Text(
                          p.body,
                          style: text.bodyLarge?.copyWith(color: t.textMuted),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: t.textMuted,
                        ),
                        child: const Text('Pular'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            key: ValueKey('intro-dot-$i'),
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 22 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page ? t.accent : t.navInactive,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 104,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('intro-next'),
                        onPressed: _next,
                        style: TextButton.styleFrom(foregroundColor: t.text),
                        child: Text(
                          _isLast ? 'Começar' : 'Próximo',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
