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

/// Confirmação do agendamento. Sem código no aparelho pede nome e telefone.
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
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;
  String? _nameError;
  String? _phoneError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final code = ref.read(deviceStoreProvider).clientCode;
    ClientInfo? info;
    if (code == null) {
      final name = _name.text.trim();
      final phoneOk = normalizePhone(_phone.text) != null;
      setState(() {
        _nameError = name.length < 2 ? 'Escreva seu nome.' : null;
        _phoneError = phoneOk
            ? null
            : 'Telefone inválido. Use DDD + número, ex.: (11) 98765-4321.';
        _error = null;
      });
      if (_nameError != null || _phoneError != null) return;
      info = ClientInfo(name: name, phone: _phone.text.trim());
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await ref
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
      if (created.clientCode != null) {
        await ref
            .read(deviceStoreProvider.notifier)
            .saveClientCode(created.clientCode!);
      }
      if (mounted) {
        Navigator.of(context).pop(ConfirmResult.booked(created.booking));
      }
    } on ApiProblem catch (e) {
      if (!mounted) return;
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
    final hasCode = ref.watch(deviceStoreProvider).clientCode != null;
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
            if (!hasCode) ...[
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
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kPhoneInputMax),
                ],
                decoration: InputDecoration(
                  labelText: 'Celular com DDD',
                  hintText: '(11) 98765-4321',
                  errorText: _phoneError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seu telefone identifica você na barbearia.',
                style: text.bodySmall,
              ),
            ] else
              Text(
                'Seus dados já estão salvos neste aparelho.',
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
