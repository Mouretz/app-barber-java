import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/phone/phone.dart';
import '../../../core/storage/device_store.dart';
import '../../../theme/theme.dart';

/// Pede nome e celular. Não preenche número nenhum.
Future<bool> showRegisterPhoneSheet(BuildContext context, WidgetRef ref) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const RegisterPhoneSheet(),
  );
  return saved == true;
}

class RegisterPhoneSheet extends ConsumerStatefulWidget {
  const RegisterPhoneSheet({super.key});

  @override
  ConsumerState<RegisterPhoneSheet> createState() => _RegisterPhoneSheetState();
}

class _RegisterPhoneSheetState extends ConsumerState<RegisterPhoneSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _nameError;
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = normalizePhone(_phone.text);
    setState(() {
      _nameError = name.length < 2 ? 'Escreva seu nome.' : null;
      _phoneError = phone != null
          ? null
          : 'Telefone inválido. Use DDD + número, ex.: (11) 98765-4321.';
    });
    if (_nameError != null || _phoneError != null || phone == null) return;
    await ref
        .read(deviceStoreProvider.notifier)
        .savePhoneDraft(phone: phone, name: name);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cadastrar telefone', style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Digite o seu número. O app não traz telefone pronto.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('register-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Seu nome',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('register-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kPhoneInputMax),
              ],
              decoration: InputDecoration(
                labelText: 'Celular com DDD',
                hintText: '(11) 98765-4321',
                hintStyle: TextStyle(color: t.textMuted),
                errorText: _phoneError,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('register-save'),
              onPressed: _save,
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
