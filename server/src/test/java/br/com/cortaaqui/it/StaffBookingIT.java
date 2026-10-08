package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

/** Casa: balcão, status, cancelar, bloqueios, agenda e corrida. Agora = 07/10/2026 09:00 (Brasília). */
class StaffBookingIT extends DomainTest {

    private Res cancelByClient(String code, UUID id) {
        return send(req(HttpMethod.POST, "/me/bookings/" + id + "/cancel").clientCode(code).newKey());
    }

    @Test
    @DisplayName("CT-03-07 duas pessoas no mesmo horário ao mesmo tempo: 1 x 201, as outras 409 SLOT_TAKEN")
    void raceSameSlot() {
        List<Callable<Res>> tasks = new ArrayList<>();
        String[] phones = {"11911110001", "11911110002", "11911110003", "11911110004", "11911110005", "11911110006"};
        for (String phone : phones) {
            tasks.add(() -> clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", phone, newCode()));
        }
        List<Res> out = together(tasks);
        assertThat(out.stream().filter(r -> r.status() == 201)).hasSize(1);
        assertThat(out.stream().filter(r -> r.status() == 409)).allSatisfy(r -> assertThat(r.code()).isEqualTo("SLOT_TAKEN"))
                .hasSize(phones.length - 1);
        assertThat(count("SELECT count(*) FROM bookings")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL")).isEqualTo(1);
    }

    @Test
    @DisplayName("CT-01-24 mesmo telefone em 3 aparelhos/pedidos simultâneos: no máximo 2 futuros pelo app")
    void raceLimit() {
        String code = newCode();
        List<Callable<Res>> tasks = List.of(
                () -> clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code),
                () -> clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, code),
                () -> clientBook(w.shopA, w.corte, w.p2, "2026-10-08T12:00", T1, code));
        List<Res> out = together(tasks);
        assertThat(out.stream().filter(r -> r.status() == 201)).hasSize(2);
        assertThat(out.stream().filter(r -> r.status() == 422).map(Res::code)).containsExactly("BOOKING_LIMIT_REACHED");
    }

    @Test
    @DisplayName("CT-04-03 / CT-04-04 cancelar exatamente 2h antes pode; 2h menos 1 s dá CANCEL_WINDOW_CLOSED")
    void cancelWindow() {
        String code = newCode();
        Res a = clientBook(w.shopA, w.corte, w.p1, "2026-10-07T12:00", T1, code);
        Res b = clientBook(w.shopA, w.corte, w.p1, "2026-10-07T13:00", T1, code);
        clock.setSp("2026-10-07T10:00:00");
        Res ok = cancelByClient(code, a.id());
        assertThat(ok.status()).isEqualTo(200);
        assertThat(ok.body().get("status").asText()).isEqualTo("CANCELED");
        assertThat(ok.body().get("canceledBy").asText()).isEqualTo("CLIENT");
        clock.setSp("2026-10-07T11:00:01");
        Res late = cancelByClient(code, b.id());
        assertThat(late.status()).isEqualTo(422);
        assertThat(late.code()).isEqualTo("CANCEL_WINDOW_CLOSED");
        // cancelar libera o horário
        clock.setSp("2026-10-07T09:00:00");
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-07")).contains("12:00").doesNotContain("13:00");
    }

    @Test
    @DisplayName("CT-00-05 cancelar 2x com a mesma chave: mesmo resultado; chave nova depois: 409 STATUS_CHANGED")
    void cancelIdempotent() {
        String code = newCode();
        Res b = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", T1, code);
        String key = UUID.randomUUID().toString();
        Res first = send(req(HttpMethod.POST, "/me/bookings/" + b.id() + "/cancel").clientCode(code).key(key));
        Res again = send(req(HttpMethod.POST, "/me/bookings/" + b.id() + "/cancel").clientCode(code).key(key));
        assertThat(first.status()).isEqualTo(200);
        assertThat(again.status()).isEqualTo(200);
        assertThat(again.body()).isEqualTo(first.body());
        Res other = cancelByClient(code, b.id());
        assertThat(other.status()).isEqualTo(409);
        assertThat(other.code()).isEqualTo("STATUS_CHANGED");
    }

    @Test
    @DisplayName("CT-05 concluir/faltou só depois do início (TOO_EARLY); status final não volta (STATUS_CHANGED)")
    void statusRules() {
        Res b = houseBook(w.corte, w.p1, "2026-10-07T10:00");
        assertThat(status(w.tGA, w.shopA, b.id(), "COMPLETED").code()).isEqualTo("TOO_EARLY");
        clock.setSp("2026-10-07T10:00:00");
        Res done = status(w.tGA, w.shopA, b.id(), "COMPLETED");
        assertThat(done.status()).as(done.toString()).isEqualTo(200);
        assertThat(done.body().get("professionalPercent").asInt() + done.body().get("shopPercent").asInt()).isEqualTo(100);
        Res back = status(w.tGA, w.shopA, b.id(), "CANCELED");
        assertThat(back.status()).isEqualTo(409);
        assertThat(back.code()).isEqualTo("STATUS_CHANGED");
        assertThat(statusInDb(b.id())).isEqualTo("COMPLETED");
    }

    @Test
    @DisplayName("CT-05 dois cliques simultâneos (concluir x faltou): um vence, o outro 409 STATUS_CHANGED")
    void raceStatus() {
        Res b = houseBook(w.corte, w.p1, "2026-10-07T09:00");
        List<Res> out = together(List.of(
                () -> status(w.tGA, w.shopA, b.id(), "COMPLETED"),
                () -> status(w.tP1, w.shopA, b.id(), "NO_SHOW")));
        assertThat(out.stream().filter(r -> r.status() == 200)).hasSize(1);
        assertThat(out.stream().filter(r -> r.status() == 409).map(Res::code)).containsExactly("STATUS_CHANGED");
    }

    @Test
    @DisplayName("Papéis: profissional muda status só do próprio (403 no do colega); outra barbearia 404 ou 403")
    void statusRoles() {
        Res b = houseBook(w.corte, w.p2, "2026-10-07T09:00");
        assertThat(status(w.tP1, w.shopA, b.id(), "NO_SHOW").code()).isEqualTo("FORBIDDEN");
        assertThat(status(w.tPB1, w.shopA, b.id(), "NO_SHOW").status()).isIn(403, 404);
        assertThat(status(w.tGB, w.shopB, b.id(), "NO_SHOW").status()).isEqualTo(404);
        assertThat(status(w.tP2, w.shopA, b.id(), "NO_SHOW").status()).isEqualTo(200);
    }

    @Test
    @DisplayName("Casa marca o slot de 30 min em andamento; o que já terminou é SLOT_IN_PAST")
    void houseCurrentSlot() {
        clock.setSp("2026-10-07T10:20:00");
        assertThat(houseBook(w.corte, w.p1, "2026-10-07T10:00").status()).isEqualTo(201);
        Res past = houseBook(w.corte, w.p1, "2026-10-07T09:30");
        assertThat(past.status()).isEqualTo(422);
        assertThat(past.code()).isEqualTo("SLOT_IN_PAST");
    }

    @Test
    @DisplayName("Balcão sem telefone: client.phone vem null; não conta no limite do app")
    void counterWithoutPhone() {
        Res r = staffBook(w.tGA, w.shopA, w.corte, w.p1, "2026-10-08T10:00", "COUNTER", "Seu Zé", null);
        assertThat(r.status()).as(r.toString()).isEqualTo(201);
        assertThat(r.body().get("client").has("phone")).isTrue();
        assertThat(r.body().get("client").get("phone").isNull()).isTrue();
        String code = newCode();
        staffBook(w.tGA, w.shopA, w.corte, w.p1, "2026-10-08T11:00", "STAFF", "João", T1);
        staffBook(w.tGA, w.shopA, w.corte, w.p1, "2026-10-08T12:00", "STAFF", "João", T1);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T13:00", T1, code).status()).isEqualTo(201);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T14:00", T1, code).status()).isEqualTo(201);
    }

    private JsonNode agendaBooking(String token, UUID pro, UUID bookingId) {
        Res agenda = get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08&professionalId=" + pro, token);
        assertThat(agenda.status()).as(agenda.toString()).isEqualTo(200);
        for (JsonNode b : agenda.body().get("professionals").get(0).get("bookings")) {
            if (b.get("id").asText().equals(bookingId.toString())) {
                return b;
            }
        }
        throw new AssertionError("agendamento fora da agenda: " + bookingId);
    }

    @Test
    @DisplayName("PO: bloqueio em cima de agendamento ativo entra (201); o agendamento fica, com overlapsBlock = true; desbloquear volta a false")
    void blockOverBookingIsAllowed() {
        Res b = houseBook(w.corte, w.p1, "2026-10-08T10:00");
        assertThat(b.body().get("overlapsBlock").asBoolean()).isFalse();
        assertThat(agendaBooking(w.tP1, w.p1, b.id()).get("overlapsBlock").asBoolean()).isFalse();

        Res block = block(w.tP1, w.shopA, w.p1, "2026-10-08T09:30", "2026-10-08T10:30");
        assertThat(block.status()).as(block.toString()).isEqualTo(201);
        assertThat(statusInDb(b.id())).isEqualTo("SCHEDULED");
        assertThat(agendaBooking(w.tP1, w.p1, b.id()).get("overlapsBlock").asBoolean()).isTrue();
        assertThat(agendaBooking(w.tGA, w.p1, b.id()).get("overlapsBlock").asBoolean()).isTrue();

        // o horário segue fora dos livres enquanto houver bloqueio
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).doesNotContain("09:30", "10:00").contains("10:30");

        assertThat(send(req(HttpMethod.DELETE, "/barbershops/" + w.shopA + "/blocks/" + block.id()).token(w.tP1)).status())
                .isEqualTo(204);
        assertThat(agendaBooking(w.tP1, w.p1, b.id()).get("overlapsBlock").asBoolean()).isFalse();
        assertThat(statusInDb(b.id())).isEqualTo("SCHEDULED");
    }

    @Test
    @DisplayName("Bloqueio em cima de outro bloqueio do mesmo profissional: 409 SLOT_TAKEN; encostado e de outro profissional pode")
    void blockOverBlockRefused() {
        assertThat(block(w.tP1, w.shopA, w.p1, "2026-10-08T12:00", "2026-10-08T13:00").status()).isEqualTo(201);
        Res over = block(w.tGA, w.shopA, w.p1, "2026-10-08T12:30", "2026-10-08T14:00");
        assertThat(over.status()).isEqualTo(409);
        assertThat(over.code()).isEqualTo("SLOT_TAKEN");
        assertThat(block(w.tGA, w.shopA, w.p1, "2026-10-08T13:00", "2026-10-08T14:00").status()).isEqualTo(201);
        assertThat(block(w.tP2, w.shopA, w.p2, "2026-10-08T12:00", "2026-10-08T13:00").status()).isEqualTo(201);
    }

    @Test
    @DisplayName("Profissional resolve o destacado: cancelar tira o overlapsBlock (só ativo conta) e o horário segue bloqueado")
    void resolveHighlighted() {
        Res b = houseBook(w.corte, w.p1, "2026-10-08T10:00");
        block(w.tP1, w.shopA, w.p1, "2026-10-08T10:00", "2026-10-08T11:00");
        Res canceled = status(w.tP1, w.shopA, b.id(), "CANCELED");
        assertThat(canceled.status()).as(canceled.toString()).isEqualTo(200);
        assertThat(canceled.body().get("overlapsBlock").asBoolean()).isFalse();
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).doesNotContain("10:00", "10:30");
    }

    @Test
    @DisplayName("Agendamento novo em cima de bloqueio: 409 SLOT_TAKEN na Casa e no app; outro profissional livre")
    void bookingOverBlockRefused() {
        assertThat(block(w.tP1, w.shopA, w.p1, "2026-10-08T12:00", "2026-10-08T13:00").status()).isEqualTo(201);
        Res house = houseBook(w.corte, w.p1, "2026-10-08T12:30");
        assertThat(house.status()).isEqualTo(409);
        assertThat(house.code()).isEqualTo("SLOT_TAKEN");
        Res partial = houseBook(w.combo, w.p1, "2026-10-08T11:30"); // 11:30-12:30 pega metade
        assertThat(partial.code()).isEqualTo("SLOT_TAKEN");
        String code = newCode();
        Res app = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", T1, code);
        assertThat(app.status()).isEqualTo(409);
        assertThat(app.code()).isEqualTo("SLOT_TAKEN");
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL")).isZero();
        assertThat(houseBook(w.corte, w.p1, "2026-10-08T13:00").status()).isEqualTo(201); // adjacente pode
        assertThat(houseBook(w.corte, w.p2, "2026-10-08T12:00").status()).isEqualTo(201);
    }

    @Test
    @DisplayName("Corrida entre agendamentos sobrepostos (Combo 10:00 x Corte 10:30) na Casa: o EXCLUDE deixa só um")
    void raceOverlappingHouseBookings() {
        List<Res> out = together(List.of(
                () -> houseBook(w.combo, w.p1, "2026-10-08T10:00"),
                () -> staffBook(w.tP1, w.shopA, w.corte, w.p1, "2026-10-08T10:30", "COUNTER", "Balcão", null)));
        assertThat(out.stream().filter(r -> r.status() == 201)).hasSize(1);
        assertThat(out.stream().filter(r -> r.status() == 409).map(Res::code)).containsExactly("SLOT_TAKEN");
    }

    @Test
    @DisplayName("Corrida bloqueio novo x agendamento novo: bloqueio sempre entra; agendamento entra ou leva SLOT_TAKEN; nunca 500")
    void raceBlockAndBooking() {
        for (int i = 0; i < 5; i++) {
            String start = String.format("2026-10-08T%02d:00", 9 + i);
            String end = String.format("2026-10-08T%02d:00", 10 + i);
            List<Res> out = together(List.of(
                    () -> block(w.tP1, w.shopA, w.p1, start, end),
                    () -> houseBook(w.corte, w.p1, start)));
            assertThat(out.get(0).status()).as(out.get(0).toString()).isEqualTo(201);
            assertThat(out.get(1).status()).as(out.get(1).toString()).isIn(201, 409);
            if (out.get(1).status() == 201) {
                assertThat(agendaBooking(w.tP1, w.p1, out.get(1).id()).get("overlapsBlock").asBoolean()).isTrue();
            }
        }
    }

    @Test
    @DisplayName("Profissional remove o próprio bloqueio, não o do colega; não bloqueia agenda alheia")
    void blockRoles() {
        Res own = block(w.tP1, w.shopA, w.p1, "2026-10-08T12:00", "2026-10-08T13:00");
        assertThat(own.status()).isEqualTo(201);
        assertThat(block(w.tP1, w.shopA, w.p2, "2026-10-08T12:00", "2026-10-08T13:00").code()).isEqualTo("FORBIDDEN");
        Res colleague = block(w.tP2, w.shopA, w.p2, "2026-10-08T12:00", "2026-10-08T13:00");
        assertThat(send(req(HttpMethod.DELETE, "/barbershops/" + w.shopA + "/blocks/" + colleague.id()).token(w.tP1)).code())
                .isEqualTo("FORBIDDEN");
        assertThat(send(req(HttpMethod.DELETE, "/barbershops/" + w.shopA + "/blocks/" + own.id()).token(w.tP1)).status())
                .isEqualTo(204);
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).contains("12:00");
    }

    @Test
    @DisplayName("Agenda: profissional vê só a própria (403 na do colega); gerente vê todos; outra barbearia 403/404")
    void agendaRoles() {
        houseBook(w.corte, w.p1, "2026-10-08T10:00");
        Res own = get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08&professionalId=" + w.p1, w.tP1);
        assertThat(own.status()).isEqualTo(200);
        assertThat(own.body().get("professionals")).hasSize(1);
        assertThat(get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08&professionalId=" + w.p2, w.tP1).code())
                .isEqualTo("FORBIDDEN");
        Res all = get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08", w.tGA);
        assertThat(all.status()).isEqualTo(200);
        assertThat(all.body().get("professionals").size()).isGreaterThanOrEqualTo(3);
        assertThat(get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08", w.tPB1).status()).isIn(403, 404);
        assertThat(get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08", null).status()).isEqualTo(401);
    }
}
