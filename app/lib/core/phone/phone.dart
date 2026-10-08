/// Tamanho do texto digitado aceito pelo contrato (`ClientInfo.phone`).
const kPhoneInputMin = 10;
const kPhoneInputMax = 20;

/// Normalização do telefone numa função só (plano da QA, seção 6, item 9).
///
/// Formato guardado e devolvido pela API (decisão do PO): `+55` + DDD + número,
/// com 10 ou 11 dígitos depois do 55 (ex.: `+5511987654321`).
///
/// Na entrada vale qualquer jeito de escrever, com máscara e com ou sem o 55:
/// - Com `+` na frente, o começo é sempre o DDI e tem que ser 55.
/// - Sem `+`: 10 ou 11 dígitos são número nacional; 12 ou 13 dígitos começando
///   com 55 são DDI + número nacional. (Proposta da QA para a pergunta 6.)
/// - Letras, DDI diferente de 55 e qualquer outro tamanho são recusados.
/// - Com 11 dígitos nacionais, o primeiro depois do DDD tem que ser 9.
/// - O texto digitado tem de 10 a 20 caracteres (`ClientInfo.phone` no
///   contrato).
///
/// Devolve `null` quando o número é inválido.
String? normalizePhone(String raw) {
  final s = raw.trim();
  if (s.length < kPhoneInputMin || s.length > kPhoneInputMax) return null;
  // Só dígitos, espaço, parênteses, hífen, ponto e um "+" no começo.
  if (!RegExp(r'^\+?[0-9\s().\-]+$').hasMatch(s)) return null;

  final digits = s.replaceAll(RegExp(r'\D'), '');
  final String national;
  if (s.startsWith('+')) {
    if (!digits.startsWith('55')) return null;
    national = digits.substring(2);
  } else if (digits.length == 10 || digits.length == 11) {
    national = digits;
  } else if ((digits.length == 12 || digits.length == 13) &&
      digits.startsWith('55')) {
    national = digits.substring(2);
  } else {
    return null;
  }

  if (national.length != 10 && national.length != 11) return null;
  if (national.startsWith('0')) return null; // DDD não começa com 0
  // Celular de 11 dígitos começa com 9 depois do DDD (igual ao `Phones` do
  // servidor no PR #3).
  if (national.length == 11 && national[2] != '9') return null;
  return '+55$national';
}

/// Número nacional (DDD + número, sem o +55).
String nationalDigits(String normalized) =>
    normalized.startsWith('+55') ? normalized.substring(3) : normalized;

/// `(11) 98765-4321` a partir do número normalizado (`+5511987654321`).
String formatPhone(String normalized) {
  final n = nationalDigits(normalized);
  if (n.length < 10) return normalized;
  final ddd = n.substring(0, 2);
  final rest = n.substring(2);
  final cut = rest.length - 4;
  return '($ddd) ${rest.substring(0, cut)}-${rest.substring(cut)}';
}
