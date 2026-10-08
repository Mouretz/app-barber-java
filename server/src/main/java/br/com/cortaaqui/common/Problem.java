package br.com.cortaaqui.common;

import java.util.List;

/** Corpo de erro no formato RFC 7807 com o {@code code} estável do contrato. */
public record Problem(String type, String title, int status, ErrorCode code, String detail, List<FieldMessage> fields) {

    public record FieldMessage(String field, String message) {
    }
}
