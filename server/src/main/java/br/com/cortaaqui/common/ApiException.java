package br.com.cortaaqui.common;

import java.util.List;
import org.springframework.http.HttpStatus;

/** Erro de regra de negócio que vira um {@link Problem} com HTTP e código estáveis. */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final ErrorCode code;
    private final String title;
    private final List<Problem.FieldMessage> fields;

    public ApiException(HttpStatus status, ErrorCode code, String title, String detail, List<Problem.FieldMessage> fields) {
        super(detail != null ? detail : title);
        this.status = status;
        this.code = code;
        this.title = title;
        this.fields = fields == null ? List.of() : List.copyOf(fields);
    }

    public ApiException(HttpStatus status, ErrorCode code, String title) {
        this(status, code, title, null, null);
    }

    public static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, ErrorCode.NOT_FOUND, "Não encontrado");
    }

    public static ApiException forbidden() {
        return new ApiException(HttpStatus.FORBIDDEN, ErrorCode.FORBIDDEN, "Sem permissão para esta ação");
    }

    public static ApiException unauthorized() {
        return new ApiException(HttpStatus.UNAUTHORIZED, ErrorCode.UNAUTHORIZED, "Não autenticado");
    }

    public static ApiException unprocessable(ErrorCode code, String title) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, code, title);
    }

    public static ApiException unprocessable(ErrorCode code, String title, String detail) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, code, title, detail, null);
    }

    public static ApiException conflict(ErrorCode code, String title) {
        return new ApiException(HttpStatus.CONFLICT, code, title);
    }

    public static ApiException invalidField(String field, String message) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.VALIDATION_ERROR, "Campo inválido", null,
                List.of(new Problem.FieldMessage(field, message)));
    }

    public HttpStatus status() {
        return status;
    }

    public ErrorCode code() {
        return code;
    }

    public String title() {
        return title;
    }

    public List<Problem.FieldMessage> fields() {
        return fields;
    }
}
