package br.com.cortaaqui.booking;

import br.com.cortaaqui.team.ProfessionalPublic;
import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Booking do contrato. Campos null não vão no JSON (o que é só da Casa some no app Cliente).
 * {@code overlapsBlock} só na Casa: agendamento ativo que bate com algum bloqueio do mesmo
 * profissional (calculado na leitura).
 */
public record BookingView(UUID id, UUID barbershopId, String barbershopName, String status, String source,
                          OffsetDateTime startAt, OffsetDateTime endAt, Ref service, ProfessionalPublic professional,
                          Client client, int priceCents, Integer shopPercent, Integer professionalPercent,
                          Boolean canCancel, String canceledBy, String note, OffsetDateTime createdAt,
                          Boolean overlapsBlock) {

    public record Ref(UUID id, String name) {
    }

    /** Quem é o cliente. A Casa recebe o telefone (null no balcão sem telefone); o app Cliente não recebe o campo. */
    public sealed interface Client permits ClientRef, ClientRefPublic {
    }

    public record ClientRef(UUID id, String name, @JsonInclude(JsonInclude.Include.ALWAYS) String phone) implements Client {
    }

    public record ClientRefPublic(UUID id, String name) implements Client {
    }
}
