import 'package:flutter/material.dart';

import '../../../core/errors/api_problem.dart';
import '../../../theme/theme.dart';

/// Rótulo de seção em caixa alta (cinza sobre o fundo preto).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// Círculo com a inicial do profissional. [selected] liga o anel amarelo
/// (um dos 4 lugares onde o amarelo pode aparecer).
class ProAvatar extends StatelessWidget {
  const ProAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.selected = false,
  });

  final String name;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? t.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: t.surface2, shape: BoxShape.circle),
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              color: t.text,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.36,
            ),
          ),
        ),
      ),
    );
  }
}

/// Carregando, sem layout pulando.
class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    return SizedBox(
      height: height,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted),
        ),
      ),
    );
  }
}

/// Erro com "Tentar de novo".
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiProblem
        ? clientMessageFor(error as ApiProblem)
        : 'Não deu para carregar.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            msg,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}

/// Card cinza padrão (`#1C1C1E`), com toque opcional.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
