package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

/** App Cliente: livres e agendar (história 1). Agora = 07/10/2026 09:00 (Brasília), salvo quando dito. */
class ClientBookingIT extends DomainTest {

    @Test
    @DisplayName("CT-01-01 agenda com P1 às 10:00: preço, duração e profissional gravados; nunca devolve código")
    void happyPath() {
        String code = newCode();
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-07T10:00", "(11) 98765-4321", code);
        assertThat(r.status()).as(r.toString()).isEqualTo(201);
        assertThat(r.body().get("status").asText()).isEqualTo("SCHEDULED");
        assertThat(r.body().get("source").asText()).isEqualTo("CLIENT_APP");
        assertThat(r.body().get("startAt").asText()).isEqualTo("2026-10-07T10:00:00-03:00");
        assertThat(r.body().get("endAt").asText()).isEqualTo("2026-10-07T10:30:00-03:00");
        assertThat(r.body().get("priceCents").asInt()).isEqualTo(4000);
        assertThat(r.body().get("professional").get("id").asText()).isEqualTo(w.p1.toString());
        assertThat(r.body().get("barbershopId").asText()).isEqualTo(w.shopA.toString());
        assertThat(r.body().has("clientCode")).isFalse();
        // app Cliente não recebe telefone, % nem nota da casa
        assertThat(r.body().get("client").has("phone")).isFalse();
        assertThat(r.body().has("shopPercent")).isFalse();
        assertThat(r.body().has("professionalPercent")).isFalse();
        assertThat(r.body().has("note")).isFalse();
        assertThat(r.body().get("canCancel").asBoolean()).isFalse(); // faltam 1h
        assertThat(db.sql("SELECT barbershop_id FROM bookings WHERE id = :id").param("id", r.id()).query(UUID.class).single())
                .isEqualTo(w.shopA);
        // só o hash do código fica no banco
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL AND phone = '5511987654321'")).isEqualTo(1);
        assertThat(db.sql("SELECT device_code_hash FROM clients WHERE phone = '5511987654321'").query(String.class).single())
                .isNotEqualTo(code).hasSize(64);
    }

    @Test
    @DisplayName("CT-01-02 exatamente 30 min antes: aparece e é aceito")
    void exactly30MinutesAhead() {
        clock.setSp("2026-10-07T09:30:00");
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-07")).first().isEqualTo("10:00");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-07T10:00", T1, newCode()).status()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-01-03 / CT-01-04 29 min (e 29:59) antes: não aparece e é recusado com TOO_SOON")
    void lessThan30Minutes() {
        clock.setSp("2026-10-07T09:31:00");
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-07")).first().isEqualTo("10:30");
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-07T10:00", T1, newCode());
        assertThat(r.status()).isEqualTo(422);
        assertThat(r.code()).isEqualTo("TOO_SOON");
        clock.setSp("2026-10-07T09:30:01");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-07T10:00", T1, newCode()).code()).isEqualTo("TOO_SOON");
        assertThat(count("SELECT count(*) FROM bookings")).isZero();
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL")).isZero(); // recusado não prende aparelho
    }

    @Test
    @DisplayName("CT-01-05 primeiro horário do dia é o início do expediente (08:00)")
    void firstSlotIsStartOfDay() {
        clock.setSp("2026-10-06T20:00:00");
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-07")).first().isEqualTo("08:00");
    }

    @Test
    @DisplayName("CT-01-06 todos os livres em :00 ou :30; 10:15 é recusado com VALIDATION_ERROR em startAt")
    void grid() {
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).allSatisfy(s -> assertThat(s).matches("\\d\\d:(00|30)"));
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:15", T1, newCode());
        assertThat(r.status()).isEqualTo(422);
        assertThat(r.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(r.body().get("fields").get(0).get("field").asText()).isEqualTo("startAt");
    }

    @Test
    @DisplayName("CT-01-07 último Corte é 18:30 (termina 19:00); 19:00 não aparece e é recusado")
    void lastCorte() {
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).last().isEqualTo("18:30");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T19:00", T1, newCode()).code()).isEqualTo("OUTSIDE_WORKING_HOURS");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T18:30", T1, newCode()).status()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-01-08 último Combo é 18:00; 18:30 não aparece e é recusado")
    void lastCombo() {
        assertThat(slots(w.shopA, w.combo, w.p1, "2026-10-08")).last().isEqualTo("18:00");
        assertThat(clientBook(w.shopA, w.combo, w.p1, "2026-10-08T18:30", T1, newCode()).code()).isEqualTo("OUTSIDE_WORKING_HOURS");
        assertThat(clientBook(w.shopA, w.combo, w.p1, "2026-10-08T18:00", T1, newCode()).status()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-01-09 07:30 (antes do expediente) é recusado")
    void beforeWorkingHours() {
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T07:30", T1, newCode()).code()).isEqualTo("OUTSIDE_WORKING_HOURS");
    }

    @Test
    @DisplayName("CT-01-10 / CT-01-12 / CT-03-02 Corte 10:30 ocupado: Combo 10:00 some e dá 409 SLOT_TAKEN")
    void comboNeedsTwoFreeSlots() {
        houseBook(w.corte, w.p1, "2026-10-08T10:30");
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).contains("10:00").doesNotContain("10:30");
        assertThat(slots(w.shopA, w.combo, w.p1, "2026-10-08")).doesNotContain("10:00", "10:30").contains("09:00", "11:00");
        Res r = clientBook(w.shopA, w.combo, w.p1, "2026-10-08T10:00", T1, newCode());
        assertThat(r.status()).isEqualTo(409);
        assertThat(r.code()).isEqualTo("SLOT_TAKEN");
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL")).isZero();
    }

    @Test
    @DisplayName("CT-01-12 Corte 10:00 ocupado: Combo 09:30 também some; 09:00 e 10:30 aparecem")
    void combo930Hidden() {
        houseBook(w.corte, w.p1, "2026-10-08T10:00");
        assertThat(slots(w.shopA, w.combo, w.p1, "2026-10-08")).doesNotContain("09:30", "10:00").contains("09:00", "10:30");
    }

    @Test
    @DisplayName("CT-01-11 bloqueio ocupa igual: Combo 10:00 some e é recusado")
    void blockOccupies() {
        assertThat(block(w.tP1, w.shopA, w.p1, "2026-10-08T10:30", "2026-10-08T11:00").status()).isEqualTo(201);
        assertThat(slots(w.shopA, w.combo, w.p1, "2026-10-08")).doesNotContain("10:00");
        assertThat(clientBook(w.shopA, w.combo, w.p1, "2026-10-08T10:00", T1, newCode()).code()).isEqualTo("SLOT_TAKEN");
    }

    @Test
    @DisplayName("CT-01-13 / CT-01-14 hoje + 13 aceito; hoje + 14 dá 422 DATE_OUT_OF_RANGE nos livres e no agendar")
    void bookingWindow() {
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-20")).isNotEmpty();
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-20T10:00", T1, newCode()).status()).isEqualTo(201);
        Res list = availability(w.shopA, w.corte, w.p1, "2026-10-21");
        assertThat(list.status()).isEqualTo(422);
        assertThat(list.code()).isEqualTo("DATE_OUT_OF_RANGE");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-21T10:00", T2, newCode()).code()).isEqualTo("DATE_OUT_OF_RANGE");
        assertThat(availability(w.shopA, w.corte, w.p1, "2026-10-06").code()).isEqualTo("DATE_OUT_OF_RANGE");
    }

    @Test
    @DisplayName("CT-01-15 horário que já passou é recusado")
    void pastRefused() {
        clock.setSp("2026-10-07T11:00:00");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-07T10:00", T1, newCode()).code()).isEqualTo("TOO_SOON");
    }

    @Test
    @DisplayName("CT-01-19 / CT-01-20 3º futuro pelo app é recusado; depois de cancelar 1, aceita")
    void limitOfTwo() {
        String code = newCode();
        Res first = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code);
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, code);
        Res third = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", T1, code);
        assertThat(third.status()).isEqualTo(422);
        assertThat(third.code()).isEqualTo("BOOKING_LIMIT_REACHED");
        assertThat(send(req(HttpMethod.POST, "/me/bookings/" + first.id() + "/cancel").clientCode(code).newKey()).status())
                .isEqualTo(200);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", T1, code).status()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-01-21 passado e status final não contam no limite")
    void pastAndFinalDontCount() {
        String code = newCode();
        clock.setSp("2026-10-01T09:00:00");
        Res a = clientBook(w.shopA, w.corte, w.p1, "2026-10-02T10:00", T1, code);
        Res b = clientBook(w.shopA, w.corte, w.p1, "2026-10-02T11:00", T1, code);
        clock.setSp("2026-10-02T12:00:00");
        status(w.tGA, w.shopA, a.id(), "COMPLETED");
        status(w.tGA, w.shopA, b.id(), "NO_SHOW");
        clock.setSp("2026-10-07T09:00:00");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code).status()).isEqualTo(201);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, code).status()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-01-23 profissional ou serviço da Barbearia B dentro da A: 404, nada gravado")
    void crossTenantIds() {
        assertThat(clientBook(w.shopA, w.corteB, w.p1, "2026-10-08T10:00", T1, newCode()).status()).isEqualTo(404);
        assertThat(clientBook(w.shopA, w.corte, w.pb1, "2026-10-08T10:00", T1, newCode()).status()).isEqualTo(404);
        assertThat(availability(w.shopA, w.corte, w.pb1, "2026-10-08").status()).isEqualTo(404);
        assertThat(count("SELECT count(*) FROM bookings")).isZero();
    }

    @Test
    @DisplayName("CT-01-27 / CT-01-28 limite soma barbearias; cancelar na A libera na B")
    void limitAcrossShops() {
        String code = newCode();
        Res a1 = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code);
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, code);
        assertThat(clientBook(w.shopB, w.corteB, w.pb1, "2026-10-08T10:00", T1, code).code()).isEqualTo("BOOKING_LIMIT_REACHED");
        send(req(HttpMethod.POST, "/me/bookings/" + a1.id() + "/cancel").clientCode(code).newKey());
        assertThat(clientBook(w.shopB, w.corteB, w.pb1, "2026-10-08T10:00", T1, code).status()).isEqualTo(201);
        assertThat(clientBook(w.shopA, w.corte, w.p2, "2026-10-08T15:00", T1, code).code()).isEqualTo("BOOKING_LIMIT_REACHED");
    }

    @Test
    @DisplayName("CT-01-29 jeitos diferentes do mesmo telefone são o mesmo cliente e somam no limite")
    void phoneVariantsSameClient() {
        String code = newCode();
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", "(11) 98765-4321", code).status()).isEqualTo(201);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", "5511987654321", code).status()).isEqualTo(201);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", "+55 11 98765-4321", code).code())
                .isEqualTo("BOOKING_LIMIT_REACHED");
        assertThat(count("SELECT count(*) FROM clients")).isEqualTo(1);
    }

    @Test
    @DisplayName("CT-00-04 mesma Idempotency-Key 2 vezes: 1 agendamento, a 2ª devolve o mesmo (200)")
    void idempotentCreate() {
        String code = newCode();
        String key = UUID.randomUUID().toString();
        Res first = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code, key);
        Res again = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code, key);
        assertThat(first.status()).isEqualTo(201);
        assertThat(again.status()).isEqualTo(200);
        assertThat(again.id()).isEqualTo(first.id());
        assertThat(count("SELECT count(*) FROM bookings")).isEqualTo(1);
        // conta 1 no limite
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, code).status()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-00-07 dados iguais com chaves diferentes são 2 pedidos: o 2º leva SLOT_TAKEN")
    void differentKeysSameData() {
        String code = newCode();
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code).code()).isEqualTo("SLOT_TAKEN");
    }

    @Test
    @DisplayName("CT-00-08 mesma chave com dados diferentes: 422 IDEMPOTENCY_KEY_REUSED")
    void sameKeyDifferentData() {
        String code = newCode();
        String key = UUID.randomUUID().toString();
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code, key);
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, code, key);
        assertThat(r.status()).isEqualTo(422);
        assertThat(r.code()).isEqualTo("IDEMPOTENCY_KEY_REUSED");
    }

    @Test
    @DisplayName("CT-00-30 servidor em UTC, 07/10 02:30 UTC = 06/10 23:30 BRT: hoje é 06/10 e o último dia é 19/10")
    void todayInSaoPaulo() {
        clock.set("2026-10-07T02:30:00Z");
        assertThat(availability(w.shopA, w.corte, w.p1, "2026-10-06").status()).isEqualTo(200);
        assertThat(availability(w.shopA, w.corte, w.p1, "2026-10-19").status()).isEqualTo(200);
        assertThat(availability(w.shopA, w.corte, w.p1, "2026-10-20").code()).isEqualTo("DATE_OUT_OF_RANGE");
    }

    @Test
    @DisplayName("CT-00-31 07/10 09:00 BRT é gravado como 12:00 UTC e devolvido com -03:00")
    void storedInUtc() {
        clock.set("2026-10-07T02:30:00Z");
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-07T09:00", T1, newCode());
        assertThat(r.body().get("startAt").asText()).isEqualTo("2026-10-07T09:00:00-03:00");
        String utc = db.sql("SELECT to_char(start_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') FROM bookings WHERE id = :id")
                .param("id", r.id()).query(String.class).single();
        assertThat(utc).isEqualTo("2026-10-07 12:00");
    }

    @Test
    @DisplayName("CT-00-32 vale a hora do servidor: pedido com offset de Lisboa é o mesmo instante")
    void serverTimeWins() {
        clock.setSp("2026-10-07T09:40:00");
        // 13:00 em Lisboa (+01:00) = 09:00 em Brasília: já passou.
        Res r = send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/bookings").clientCode(newCode()).newKey()
                .body(map("serviceId", w.corte, "professionalId", w.p1, "startAt", "2026-10-07T14:00:00+01:00",
                        "client", map("name", "Cliente", "phone", T1))));
        assertThat(r.code()).isEqualTo("TOO_SOON"); // 10:00 BRT, 20 min de antecedência real
    }

    // ------------------------------------------------------------------ código do aparelho

    @Test
    @DisplayName("Código ausente, mal formado ou liberado no agendar: 401 com a mesma resposta")
    void badCodeOnCreate() {
        Res missing = send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/bookings").newKey()
                .body(map("serviceId", w.corte, "professionalId", w.p1, "startAt", sp("2026-10-08T10:00"),
                        "client", map("name", "Cliente", "phone", T1))));
        Res malformed = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, "nao-e-uuid-1234567890");
        assertThat(missing.status()).isEqualTo(401);
        assertThat(malformed.status()).isEqualTo(401);
        assertThat(malformed.body()).isEqualTo(missing.body());
        assertThat(missing.code()).isEqualTo("UNAUTHORIZED");
    }

    @Test
    @DisplayName("Telefone preso a outro aparelho: 409 PHONE_ON_OTHER_DEVICE e nada criado")
    void phoneOnOtherDevice() {
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", "(11) 98765-4321", newCode());
        assertThat(r.status()).isEqualTo(409);
        assertThat(r.code()).isEqualTo("PHONE_ON_OTHER_DEVICE");
        assertThat(r.body().get("title").asText()).isEqualTo("Esse telefone já está em outro aparelho. Fale com a barbearia.");
        assertThat(count("SELECT count(*) FROM bookings")).isEqualTo(1);
    }

    @Test
    @DisplayName("Aparelho preso ao João mandando o telefone do Rafael (preso a outro): 409 DEVICE_PHONE_MISMATCH primeiro")
    void deviceMismatchComesFirst() {
        String joaoDevice = newCode();
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, joaoDevice);
        clientBook(w.shopA, w.corte, w.p2, "2026-10-08T10:00", T2, newCode()); // Rafael preso a outro aparelho
        Res r = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T2, joaoDevice);
        assertThat(r.status()).isEqualTo(409);
        assertThat(r.code()).isEqualTo("DEVICE_PHONE_MISMATCH");
    }

    @Test
    @DisplayName("Aparelho preso a um telefone mandando telefone novo (livre): 409 DEVICE_PHONE_MISMATCH, sem trocar o vínculo")
    void deviceMismatchNoRebind() {
        String code = newCode();
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T2, code).code()).isEqualTo("DEVICE_PHONE_MISMATCH");
        assertThat(count("SELECT count(*) FROM clients WHERE phone = '" + T2 + "'")).isZero();
    }

    @Test
    @DisplayName("Agendamento recusado não prende o aparelho; o próximo aparelho que agendar com sucesso prende")
    void refusedDoesNotBind() {
        String first = newCode();
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-21T10:00", T1, first).code()).isEqualTo("DATE_OUT_OF_RANGE");
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T19:00", T1, first).code()).isEqualTo("OUTSIDE_WORKING_HOURS");
        String second = newCode();
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, second).status()).isEqualTo(201);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, first).code()).isEqualTo("PHONE_ON_OTHER_DEVICE");
    }
}
