import '../time/sao_paulo.dart';

/// `R$ 40,00` a partir de centavos. Dinheiro sempre em centavos inteiros.
String formatCents(int cents) {
  final reais = cents ~/ 100;
  final centavos = (cents % 100).toString().padLeft(2, '0');
  final s = reais.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return 'R\$ $buf,$centavos';
}

/// `30 min` ou `1h` / `1h30`.
String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

const _weekdaysShort = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const _weekdaysLong = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];
const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

String weekdayShort(SpDate d) => _weekdaysShort[d.weekday - 1];

String monthShort(SpDate d) => _months[d.month - 1];

/// `hoje`, `amanhã` ou `qui, 15 out`.
String formatDayLabel(SpDate d, SpDate today) {
  final diff = today.daysUntil(d);
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  return '${weekdayShort(d)}, ${d.day} ${monthShort(d)}';
}

/// `Amanhã, 10:00` / `Quinta, 15 out · 10:00`.
String formatBookingWhen(DateTime start, SpDate today) {
  final d = SpDate.of(start);
  final diff = today.daysUntil(d);
  final hm = formatHm(start);
  if (diff == 0) return 'Hoje, $hm';
  if (diff == 1) return 'Amanhã, $hm';
  final wd = _weekdaysLong[d.weekday - 1];
  final cap = wd[0].toUpperCase() + wd.substring(1);
  return '$cap, ${d.day} ${monthShort(d)} · $hm';
}
