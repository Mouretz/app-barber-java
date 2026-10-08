package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
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

    @Test
    @DisplayName("Bloqueio em cima de agendamento é recusado (SLOT_TAKEN); profissional remove o próprio, não o do colega")
    void blocks() {
        houseBook(w.corte, w.p1, "2026-10-08T10:00");
        assertThat(block(w.tP1, w.shopA, w.p1, "2026-10-08T09:30", "2026-10-08T10:30").code()).isEqualTo("SLOT_TAKEN");
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
