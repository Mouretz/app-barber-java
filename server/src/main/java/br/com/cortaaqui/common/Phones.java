package br.com.cortaaqui.common;

import java.util.regex.Pattern;

/**
 * Normalização de telefone, num lugar só (app, Casa, balcão, cadastro e busca).
 * Resultado: só dígitos, 55 + DDD + número, com 10 ou 11 dígitos depois do 55.
 * Ex.: "(11) 98765-4321", "11987654321", "+55 11 98765-4321" e "5511987654321" viram "5511987654321".
 */
public final class Phones {

    private static final Pattern ALLOWED = Pattern.compile("^[0-9 ()\\-.]+$");
    private static final Pattern NATIONAL = Pattern.compile("^[1-9]{2}[0-9]{8,9}$");

    private Phones() {
    }

    public static String normalize(String raw) {
        String result = tryNormalize(raw);
        if (result == null) {
            throw ApiException.invalidField("phone", "telefone inválido: use DDD + número (10 ou 11 dígitos), do Brasil");
        }
        return result;
    }

    /** Como a API devolve: E.164, "+5511987654321". No banco fica sem o "+". */
    public static String display(String stored) {
        return stored == null ? null : "+" + stored;
    }

    /** Devolve o número normalizado (só dígitos, começando com 55) ou null se for inválido. */
    public static String tryNormalize(String raw) {
        if (raw == null) {
            return null;
        }
        String s = raw.strip();
        boolean plus = s.startsWith("+");
        if (plus) {
            s = s.substring(1);
        }
        if (s.isEmpty() || !ALLOWED.matcher(s).matches()) {
            return null;
        }
        String digits = s.replaceAll("[^0-9]", "");
        String national;
        if (plus) {
            if (!digits.startsWith("55")) {
                return null; // DDI diferente de 55
            }
            national = digits.substring(2);
        } else if (digits.length() == 10 || digits.length() == 11) {
            national = digits;
        } else if ((digits.length() == 12 || digits.length() == 13) && digits.startsWith("55")) {
            national = digits.substring(2);
        } else {
            return null;
        }
        if (!NATIONAL.matcher(national).matches()) {
            return null;
        }
        if (national.length() == 11 && national.charAt(2) != '9') {
            return null; // celular com 11 dígitos começa com 9
        }
        return "55" + national;
    }
}
