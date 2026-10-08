import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_problem.dart';
import '../../../core/format/formatters.dart';
import '../../../core/ids/uuid.dart';
import '../../../core/phone/phone.dart';
import '../../../core/storage/device_store.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/barbershop.dart';
import '../../../data/models/booking.dart';
import '../../../theme/theme.dart';
import '../providers.dart';

/// Resultado da confirmação: agendou, ou o horário escapou (volta a escolher).
class ConfirmResult {
  const ConfirmResult.booked(Booking this.booking) : slotLostMessage = null;
  const ConfirmResult.slotLost(String this.slotLostMessage) : booking = null;

  final Booking? booking;
  final String? slotLostMessage;
}

/// Erros em que o horário escolhido não vale mais: fecha a folha e volta para a
/// lista de horários recarregada.
const _slotLostCodes = {
  ErrorCode.slotTaken,
  ErrorCode.tooSoon,
  ErrorCode.outsideWorkingHours,
  ErrorCode.dateOutOfRange,
};

/// Confirmação do agendamento. Pede nome e telefone; com o aparelho já preso
/// a um telefone, o campo de telefone vem travado com o número salvo.
///
/// O código do aparelho nasce aqui (o app gera, CT-04-14) e vai em
/// `X-Client-Code`. Ele só é guardado, e o telefone só trava, quando o
/// agendamento é aceito. Recusa não guarda nada.
///
/// Pedido repetido: a chave de idempotência é gerada uma vez por confirmação
/// (ao abrir a folha) e o botão trava enquanto envia. Dois toques mandam a
/// mesma chave, e o repositório devolve o mesmo agendamento.
class ConfirmBookingSheet extends ConsumerStatefulWidget {
  const ConfirmBookingSheet({
    super.key,
    required this.shop,
    required this.service,
    required this.professional,
    required this.startAt,
  });

  final BarbershopDetail shop;
  final Service service;
  final ProfessionalPublic professional;
  final DateTime startAt;

  @override
  ConsumerState<ConfirmBookingSheet> createState() =>
      _ConfirmBookingSheetState();
}

class _ConfirmBookingSheetState extends ConsumerState<ConfirmBookingSheet> {
  final String _idempotencyKey = newUuid();

  /// Código novo para o aparelho que ainda não está preso a um telefone. Só é
  /// guardado se o agendamento for aceito.
  final String _candidateCode = newClientCode();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;
  String? _nameError;
  String? _phoneError;
  String? _error;

  @override
  void initState() {
    super.initState();
    final device = ref.read(deviceStoreProvider);
    _name.text = device.clientName ?? '';
    if (device.hasSession) _phone.text = formatPhone(device.boundPhone!);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final device = ref.read(deviceStoreProvider);
    final bound = device.hasSession;
    final name = _name.text.trim();
    final phone = bound ? device.boundPhone : normalizePhone(_phone.text);
    setState(() {
      _nameError = name.length < 2 ? 'Escreva seu nome.' : null;
      _phoneError = phone != null
          ? null
          : 'Telefone inválido. Use DDD + número, ex.: (11) 98765-4321.';
      _error = null;
    });
    if (_nameError != null || _phoneError != null) return;
    final code = bound ? device.clientCode! : _candidateCode;
    final info = ClientInfo(
      name: name,
      phone: bound ? device.boundPhone! : _phone.text.trim(),
    );

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final booking = await ref
          .read(clienteRepositoryProvider)
          .createClientBooking(
            barbershopId: widget.shop.id,
            idempotencyKey: _idempotencyKey,
            clientCode: code,
            request: ClientBookingRequest(
              serviceId: widget.service.id,
              professionalId: widget.professional.id,
              startAt: widget.startAt,
              client: info,
            ),
          );
      // Aceito: só agora o aparelho fica preso ao telefone.
      if (!bound) {
        await ref
            .read(deviceStoreProvider.notifier)
            .bindAfterAcceptedBooking(code: code, phone: phone!, name: name);
      }
      if (mounted) {
        Navigator.of(context).pop(ConfirmResult.booked(booking));
      }
    } on ApiProblem catch (e) {
      if (!mounted) return;
      if (e.code == ErrorCode.unauthorized ||
          e.code == ErrorCode.devicePhoneMismatch) {
        // Código revogado (troca de celular) ou preso a outro número: o
        // aparelho volta ao estado sem código e o telefone destrava.
        await ref.read(deviceStoreProvider.notifier).clearSession();
        if (!mounted) return;
      }
      if (_slotLostCodes.contains(e.code)) {
        Navigator.of(context).pop(ConfirmResult.slotLost(clientMessageFor(e)));
        return;
      }
      setState(() {
        _submitting = false;
        if (e.hasField('phone')) {
          _phoneError = clientMessageFor(e);
        } else if (e.hasField('name')) {
          _nameError = clientMessageFor(e);
        } else {
          _error = clientMessageFor(e);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Algo deu errado. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final text = Theme.of(context).textTheme;
    final locked = ref.watch(deviceStoreProvider).hasSession;
    final today = SpDate.of(ref.watch(clockProvider).now());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Confirmar horário', style: text.headlineSmall),
            const SizedBox(height: 16),
            _Row(
              label: 'Quando',
              value: formatBookingWhen(widget.startAt, today),
            ),
            _Row(
              label: 'Serviço',
              value:
                  '${widget.service.name} · ${formatDuration(widget.service.durationMinutes)}',
            ),
            _Row(label: 'Profissional', value: widget.professional.name),
            _Row(label: 'Barbearia', value: widget.shop.name),
            _Row(label: 'Valor', value: formatCents(widget.service.priceCents)),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('confirm-name'),
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
              key: const ValueKey('confirm-phone'),
              controller: _phone,
              // Só leitura (não `enabled: false`): o texto continua branco.
              readOnly: locked,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kPhoneInputMax),
              ],
              decoration: InputDecoration(
                labelText: 'Celular com DDD',
                hintText: '(11) 98765-4321',
                // Placeholder em #8E8E93 sobre o campo #1C1C1E (5,21:1). O
                // O cinza escuro do tema para placeholder reprova (CT-09-11).
                hintStyle: TextStyle(color: t.textMuted),
                errorText: _phoneError,
                errorMaxLines: 2,
                suffixIcon: locked
                    ? Icon(Icons.lock_outline, size: 18, color: t.textMuted)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              locked
                  ? 'Este aparelho está ligado a este telefone.'
                  : 'Seu telefone identifica você na barbearia.',
              key: const ValueKey('confirm-phone-note'),
              style: text.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('confirm-error'),
                style: text.bodyMedium?.copyWith(color: t.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('confirm-submit'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.textMutedOnSurface2,
                      ),
                    )
                  : const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label, style: text.bodySmall)),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}
