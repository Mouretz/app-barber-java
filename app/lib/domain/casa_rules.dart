import '../core/errors/api_problem.dart';
import 'scheduling.dart';

/// Regras da Casa que o app confere antes de mandar (o servidor confere de
/// novo e responde com os mesmos códigos).
abstract final class CasaRules {
  /// Expediente só entre 08:00 e 21:00 (regra do PO, 08/10).
  static const int openMinute = 8 * 60;
  static const int closeMinute = 21 * 60;

  static const int minServiceMinutes = 30;
  static const int maxServiceMinutes = 480;
}

ApiProblem _invalid(String field, String message) => ApiProblem(
  ErrorCode.validationError,
  status: 422,
  title: 'Dados inválidos',
  fields: [ProblemField(field, message)],
);

/// Janela de expediente: entre 08:00 e 21:00, na grade de 30 min, fim depois
/// do início (CT-07-05, CT-07-08, CT-07-09). Fim às 00:00 não vale aqui.
ApiProblem? checkWorkWindow(WorkWindow w, {String field = 'windows'}) {
  if (w.startMinute % SchedulingRules.slotMinutes != 0 ||
      w.startMinute < CasaRules.openMinute ||
      w.startMinute >= CasaRules.closeMinute) {
    return _invalid(
      '$field.start',
      'Início entre 08:00 e 20:30, de 30 em 30 min',
    );
  }
  if (w.endMinute % SchedulingRules.slotMinutes != 0 ||
      w.endMinute > CasaRules.closeMinute ||
      w.endMinute <= w.startMinute) {
    return _invalid(
      '$field.end',
      'Fim até 21:00, depois do início, de 30 em 30 min',
    );
  }
  return null;
}

/// Até 3 janelas por dia, sem sobreposição.
ApiProblem? checkDayWindows(
  List<WorkWindow> windows, {
  String field = 'windows',
}) {
  if (windows.length > 3) return _invalid(field, 'Até 3 janelas por dia');
  final sorted = [...windows]..sort((a, b) => a.startMinute - b.startMinute);
  for (var i = 0; i < sorted.length; i++) {
    final p = checkWorkWindow(sorted[i], field: '$field[$i]');
    if (p != null) return p;
    if (i > 0 && sorted[i].startMinute < sorted[i - 1].endMinute) {
      return _invalid('$field[$i].start', 'Janelas não podem se sobrepor');
    }
  }
  return null;
}

/// Duração do serviço: 30 a 480 min, múltiplo de 30 (CT-10-06, CT-10-07).
ApiProblem? checkServiceDuration(int minutes) {
  if (minutes < CasaRules.minServiceMinutes ||
      minutes > CasaRules.maxServiceMinutes ||
      minutes % SchedulingRules.slotMinutes != 0) {
    return _invalid('durationMinutes', 'De 30 a 480 min, em múltiplos de 30');
  }
  return null;
}

/// % inteiro de 0 a 100 que soma 100 com a casa (CT-20-02, CT-20-03).
ApiProblem? checkSplit(int shopPercent, int professionalPercent) {
  bool ok(int v) => v >= 0 && v <= 100;
  if (!ok(shopPercent) || !ok(professionalPercent)) {
    return _invalid('professionalPercent', 'Número inteiro de 0 a 100');
  }
  if (shopPercent + professionalPercent != 100) {
    return const ApiProblem(
      ErrorCode.commissionSumInvalid,
      status: 422,
      title: 'A soma tem que dar 100',
    );
  }
  return null;
}
