package br.com.cortaaqui.common;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import org.springframework.http.HttpStatus;

/**
 * Validação de entrada feita no serviço, depois da checagem de papel. Assim quem não tem
 * permissão recebe 403 antes de qualquer 422 (varredura CT-00-24).
 */
public final class Checks {

    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");

    private final List<Problem.FieldMessage> errors = new ArrayList<>();

    public static Checks start() {
        return new Checks();
    }

    public Checks required(String field, Object value) {
        if (value == null) {
            add(field, "obrigatório");
        }
        return this;
    }

    public Checks text(String field, String value, int min, int max, boolean required) {
        if (value == null) {
            if (required) {
                add(field, "obrigatório");
            }
            return this;
        }
        int len = value.strip().length();
        if (len < min || value.length() > max) {
            add(field, "deve ter entre " + min + " e " + max + " caracteres");
        }
        return this;
    }

    public Checks email(String field, String value) {
        if (value != null && (value.length() > 120 || !EMAIL.matcher(value).matches())) {
            add(field, "e-mail inválido");
        }
        return this;
    }

    public Checks range(String field, Integer value, int min, int max) {
        if (value != null && (value < min || value > max)) {
            add(field, "deve estar entre " + min + " e " + max);
        }
        return this;
    }

    /** Entre {@code min} e {@code max}, em passos de {@code step} (ex.: duração 30, 60, 90...). Uma mensagem só. */
    public Checks rangeStep(String field, Integer value, int min, int max, int step) {
        if (value != null && (value < min || value > max || value % step != 0)) {
            add(field, "deve estar entre " + min + " e " + max + ", em múltiplos de " + step);
        }
        return this;
    }

    public Checks isTrue(boolean ok, String field, String message) {
        if (!ok) {
            add(field, message);
        }
        return this;
    }

    public Checks add(String field, String message) {
        errors.add(new Problem.FieldMessage(field, message));
        return this;
    }

    public boolean ok() {
        return errors.isEmpty();
    }

    public void orThrow() {
        if (!errors.isEmpty()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.VALIDATION_ERROR, "Dados inválidos", null, errors);
        }
    }
}
