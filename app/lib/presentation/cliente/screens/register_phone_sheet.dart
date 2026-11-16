import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/phone/phone.dart';
import '../../../core/storage/device_store.dart';
import '../../../theme/theme.dart';

/// Pede nome, sobrenome, apelido e celular. O Início não mostra o número.
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
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _nick = TextEditingController();
  final _phone = TextEditingController();
  String? _firstError;
  String? _lastError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    final device = ref.read(deviceStoreProvider);
    _first.text = device.firstName ?? '';
    _last.text = device.lastName ?? '';
    _nick.text = device.nickname ?? '';
    if (device.phoneOnFile != null) {
      _phone.text = formatPhone(device.phoneOnFile!);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _nick.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final first = _first.text.trim();
    final last = _last.text.trim();
    final nick = _nick.text.trim();
    final phone = normalizePhone(_phone.text);
    setState(() {
      _firstError = first.length < 2 ? 'Escreva seu nome.' : null;
      _lastError = last.length < 2 ? 'Escreva seu sobrenome.' : null;
      _phoneError = phone != null
          ? null
          : 'Telefone inválido. Use DDD + número, ex.: (11) 98765-4321.';
    });
    if (_firstError != null || _lastError != null || phone == null) return;
    await ref
        .read(deviceStoreProvider.notifier)
        .savePhoneDraft(
          phone: phone,
          firstName: first,
          lastName: last,
          nickname: nick,
        );
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
            Text('Seus dados', style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'O Início mostra nome, sobrenome e apelido. O telefone fica no Menu.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('register-name'),
              controller: _first,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nome',
                errorText: _firstError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('register-last'),
              controller: _last,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Sobrenome',
                errorText: _lastError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('register-nick'),
              controller: _nick,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Apelido'),
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
