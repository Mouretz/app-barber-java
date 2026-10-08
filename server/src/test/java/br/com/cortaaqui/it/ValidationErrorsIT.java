package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

/**
 * 422 VALIDATION_ERROR por tipo errado ou corpo ilegível vem no formato normal do contrato
 * (Problem com fields), apontando o campo ou parâmetro quando dá para saber.
 */
class ValidationErrorsIT extends DomainTest {

    private Res postService(String rawJson) {
        return send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/services").token(w.tGA).body(rawJson));
    }

    private Res postBooking(String rawJson) {
        return send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/bookings").clientCode(newCode()).newKey().body(rawJson));
    }

    private static void assertField(Res r, String field) {
        assertThat(r.status()).as(r.toString()).isEqualTo(422);
        assertThat(r.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(r.body().get("status").asInt()).isEqualTo(422);
        assertThat(r.body().get("title").asText()).isNotBlank();
        JsonNode fields = r.body().get("fields");
        assertThat(fields).as(r.toString()).isNotNull();
        assertThat(fields.isArray()).isTrue();
        assertThat(fields).hasSize(1);
        assertThat(fields.get(0).get("field").asText()).isEqualTo(field);
        assertThat(fields.get(0).get("message").asText()).isNotBlank();
    }

    @Test
    @DisplayName("Texto onde vai número e 60.5 em campo inteiro: 422 com fields apontando o campo")
    void wrongNumberType() {
        assertField(postService("{\"name\":\"Corte X\":\"durationMinutes\":30,\"priceCents\":\"abc\"}"), "priceCents");
        assertField(postService("{\"name\":\"Corte X\":\"durationMinutes\":30.5,\"priceCents\":4000}"), "durationMinutes");
        assertField(postService("{\"name\":\"Corte X\":\"durationMinutes\":\"30\",\"priceCents\":4000}"), "durationMinutes");
        assertThat(count("SELECT count(*) FROM services WHERE name = 'Corte X'")).isZero();
    }

    @Test
    @DisplayName("UUID e data inválidos no corpo, e tipo errado em campo aninhado: fields com o caminho do campo")
    void wrongTypesInBooking() {
        String client = "\"client\":{\"name\":\"Ana\":\"phone\":\"11911112222\"}";
        assertField(postBooking("{\"serviceId\":\"nao-e-uuid\",\"professionalId\":\"" + w.p1
                + "\",\"startAt\":\"" + sp("2026-10-08T10:00") + "\"," + client + "}"), "serviceId");
        assertField(postBooking("{\"serviceId\":\"" + w.corte + "\",\"professionalId\":\"" + w.p1
                + "\",\"startAt\":\"amanhã\"," + client + "}"), "startAt");
        assertField(postBooking("{\"serviceId\":\"" + w.corte + "\",\"professionalId\":\"" + w.p1
                + "\",\"startAt\":\"" + sp("2026-10-08T10:00") + "\",\"client\":{\"name\":\"Ana\":\"phone\":\"11911112222\",\"email\":{}}}"),
                "client.email");
        assertThat(count("SELECT count(*) FROM bookings")).isZero();
    }

    @Test
    @DisplayName("JSON quebrado ou corpo vazio: 422 com fields = body")
    void unreadableBody() {
        assertField(postService("{\"name\":"), "body");
        assertField(send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/services").token(w.tGA)
                .body("")), "body");
    }

    @Test
    @DisplayName("Parâmetro e cabeçalho com tipo errado: 422 com fields apontando o parâmetro")
    void wrongParamTypes() {
        assertField(send(req(HttpMethod.GET, "/barbershops/" + w.shopA + "/availability?serviceId=" + w.corte
                + "&professionalId=" + w.p1 + "&date=amanha")), "date");
        assertField(send(req(HttpMethod.GET, "/barbershops/" + w.shopA + "/availability?serviceId=xyz"
                + "&professionalId=" + w.p1 + "&date=2026-10-08")), "serviceId");
        assertField(send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/bookings").clientCode(newCode())
                .key("nao-e-uuid").body(map("serviceId", w.corte))), "Idempotency-Key");
    }
}
