package br.com.cortaaqui.common;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.sql.SQLException;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);
    public static final MediaType PROBLEM_JSON = MediaType.APPLICATION_PROBLEM_JSON;

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<Problem> api(ApiException e) {
        return respond(e);
    }

    /**
     * A trava do banco: violação do EXCLUDE (23P01) vira 409 SLOT_TAKEN, nunca 500.
     * Telefone repetido na mesma barbearia vira 409 PHONE_IN_USE.
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<Problem> integrity(DataIntegrityViolationException e) {
        ApiException mapped = mapIntegrity(e);
        if (mapped == null) {
            log.warn("violação de integridade não mapeada", e);
            mapped = ApiException.conflict(ErrorCode.VALIDATION_ERROR, "Conflito com dados existentes");
        }
        return respond(mapped);
    }

    public static ApiException mapIntegrity(Throwable e) {
        SQLException sql = findSql(e);
        if (sql == null) {
            return null;
        }
        String state = sql.getSQLState();
        String msg = String.valueOf(sql.getMessage());
        if ("23P01".equals(state)) {
            return ApiException.conflict(ErrorCode.SLOT_TAKEN, "Horário ocupado");
        }
        if ("23505".equals(state) && msg.contains("uk_client_profiles_client")) {
            return ApiException.conflict(ErrorCode.PHONE_IN_USE, "Já existe cliente com esse telefone nesta barbearia");
        }
        if ("23505".equals(state) && msg.contains("uk_staff_users_email")) {
            return ApiException.conflict(ErrorCode.EMAIL_IN_USE, "E-mail já usado");
        }
        if ("23514".equals(state) && msg.contains("ck_bookings_status_forward_only")) {
            return ApiException.conflict(ErrorCode.STATUS_CHANGED, "O status desse horário já mudou");
        }
        return null;
    }

    private static SQLException findSql(Throwable e) {
        Throwable t = e;
        while (t != null) {
            if (t instanceof SQLException s) {
                return s;
            }
            t = t.getCause();
        }
        return null;
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Problem> unreadable(HttpMessageNotReadableException e) {
        return respond(new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.VALIDATION_ERROR,
                "Corpo inválido", "JSON inválido ou campo com tipo errado", null));
    }

    @ExceptionHandler(MissingRequestHeaderException.class)
    public ResponseEntity<Problem> missingHeader(MissingRequestHeaderException e) {
        return respond(ApiException.invalidField(e.getHeaderName(), "cabeçalho obrigatório"));
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<Problem> missingParam(MissingServletRequestParameterException e) {
        return respond(ApiException.invalidField(e.getParameterName(), "obrigatório"));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<Problem> typeMismatch(MethodArgumentTypeMismatchException e) {
        boolean path = e.getParameter().hasParameterAnnotation(org.springframework.web.bind.annotation.PathVariable.class);
        if (path) {
            return respond(ApiException.notFound());
        }
        return respond(ApiException.invalidField(e.getName(), "valor inválido"));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<Problem> noResource(NoResourceFoundException e) {
        return respond(ApiException.notFound());
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<Problem> method(HttpRequestMethodNotSupportedException e) {
        return respond(new ApiException(HttpStatus.METHOD_NOT_ALLOWED, ErrorCode.NOT_FOUND, "Método não suportado"));
    }

    private static Problem body(ApiException e) {
        return new Problem("about:blank", e.title(), e.status().value(), e.code(),
                e.getMessage().equals(e.title()) ? null : e.getMessage(), e.fields().isEmpty() ? null : List.copyOf(e.fields()));
    }

    private static ResponseEntity<Problem> respond(ApiException e) {
        return ResponseEntity.status(e.status()).contentType(PROBLEM_JSON).body(body(e));
    }

    /** Usado pelos handlers do Spring Security (fora do DispatcherServlet). */
    public static void write(HttpServletResponse res, ObjectMapper mapper, ApiException e) throws IOException {
        res.setStatus(e.status().value());
        res.setContentType(PROBLEM_JSON.toString());
        res.setCharacterEncoding("UTF-8");
        mapper.writeValue(res.getOutputStream(), body(e));
    }
}
