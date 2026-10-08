package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import br.com.cortaaqui.support.DomainTest;
import br.com.cortaaqui.support.World;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpMethod;

/**
 * Respostas do PO (08/10) às 6 perguntas em aberto do plano da QA (PR #7). A 4 (intro) é só do app.
 * 1 e 2: expediente entre 08:00 e 21:00, na grade de 30 min; turno pelo início.
 * 3: duração do serviço em múltiplos de 30. 5: profissional busca e cadastra cliente, editar ficha
 * e liberar aparelho são do gerente. 6: profissional desativado perde o acesso à Casa e pode ser reativado.
 */
class RegrasPoPlanoIT extends DomainTest {

    // ------------------------------------------------------------------ helpers

    private Res putHours(String token, UUID shop, UUID pro, String weekday, String start, String end) {
        return send(req(HttpMethod.PUT, "/barbershops/" + shop + "/professionals/" + pro + "/working-hours").token(token)
                .body(map("days", List.of(map("weekday", weekday, "windows", List.of(map("start", start, "end", end)))))));
    }

    private Res putAllDays(String token, UUID shop, UUID pro, String start, String end) {
        List<Object> days = new ArrayList<>();
        for (String d : List.of("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")) {
            days.add(map("weekday", d, "windows", List.of(map("start", start, "end", end))));
        }
        return send(req(HttpMethod.PUT, "/barbershops/" + shop + "/professionals/" + pro + "/working-hours").token(token)
                .body(map("days", days)));
    }

    private Res getHours(UUID shop, UUID pro) {
        return get("/barbershops/" + shop + "/professionals/" + pro + "/working-hours", w.tGA);
    }

    private static List<String> fields(Res r) {
        List<String> out = new ArrayList<>();
        if (r.body() != null && r.body().get("fields") != null) {
            for (JsonNode f : r.body().get("fields")) {
                out.add(f.get("field").asText());
            }
        }
        return out;
    }

    private void assertValidation(Res r, String field) {
        assertThat(r.status()).as(r.toString()).isEqualTo(422);
        assertThat(r.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(fields(r)).as(r.toString()).containsExactly(field);
    }

    private Res login(String email, String password) {
        return send(req(HttpMethod.POST, "/auth/login").body(map("email", email, "password", password)));
    }

    private Res setActive(String token, UUID shop, UUID pro, boolean active) {
        return send(req(HttpMethod.PATCH, "/barbershops/" + shop + "/professionals/" + pro).token(token)
                .body(map("active", active)));
    }

    private Res createService(int minutes) {
        return send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/services").token(w.tGA)
                .body(map("name", "Serviço " + minutes, "durationMinutes", minutes, "priceCents", 1000)));
    }

    private Res patchService(UUID id, Object minutes) {
        return send(req(HttpMethod.PATCH, "/barbershops/" + w.shopA + "/services/" + id).token(w.tGA)
                .body(map("durationMinutes", minutes)));
    }

    private int durationInDb(UUID serviceId) {
        return db.sql("SELECT duration_minutes FROM services WHERE id = :id").param("id", serviceId).query(Integer.class).single();
    }

    private Res putDay(String weekday, String start, String end) {
        return putHours(w.tGA, w.shopA, w.p1, weekday, start, end);
    }

    private void assertOldHoursKept() {
        JsonNode days = getHours(w.shopA, w.p1).body().get("days");
        assertThat(days).hasSize(7);
        for (JsonNode d : days) {
            assertThat(d.get("windows")).hasSize(1);
            assertThat(d.get("windows").get(0).get("start").asText()).isEqualTo("08:00");
            assertThat(d.get("windows").get(0).get("end").asText()).isEqualTo("19:00");
        }
    }

    private Res patchClient(String token, UUID shop, UUID id, Object body) {
        return send(req(HttpMethod.PATCH, "/barbershops/" + shop + "/clients/" + id).token(token).body(body));
    }

    private Res createClient(String token, UUID shop, String name, String phone) {
        return send(req(HttpMethod.POST, "/barbershops/" + shop + "/clients").token(token)
                .body(map("name", name, "phone", phone)));
    }

    private boolean isActive(UUID pro) {
        return db.sql("SELECT active FROM professionals WHERE id = :p").param("p", pro).query(Boolean.class).single();
    }

    // ------------------------------------------------------------------ 1 e 2: expediente 08:00–21:00 na grade de 30

    @Test
    @DisplayName("CT-07-08: terça 08:00–21:00 aceito (livres de Corte 08:00 a 20:30); 07:30–18:00, 09:00–21:30 e 10:00–00:00 dão 422 no campo")
    void ct0708MvpWindow() {
        String base = "days[0].windows[0]";
        assertValidation(putDay("TUE", "07:30", "18:00"), base + ".start");
        assertValidation(putDay("TUE", "09:00", "21:30"), base + ".end");
        assertValidation(putDay("TUE", "10:00", "00:00"), base + ".end");
        assertValidation(putDay("TUE", "00:00", "12:00"), base + ".start");
        assertValidation(putDay("TUE", "21:00", "21:30"), base + ".end");
        Res both = putDay("TUE", "06:00", "22:00");
        assertThat(both.status()).isEqualTo(422);
        assertThat(fields(both)).containsExactly(base + ".start", base + ".end");
        assertOldHoursKept();

        Res ok = putDay("TUE", "08:00", "21:00");
        assertThat(ok.status()).as(ok.toString()).isEqualTo(200);
        JsonNode win = ok.body().get("days").get(0).get("windows").get(0);
        assertThat(win.get("start").asText()).isEqualTo("08:00");
        assertThat(win.get("end").asText()).isEqualTo("21:00");
        List<String> corte = slots(w.shopA, w.corte, w.p1, "2026-10-13"); // terça
        assertThat(corte).first().isEqualTo("08:00");
        assertThat(corte).last().isEqualTo("20:30");
        assertThat(corte).hasSize(26);
    }

    @Test
    @DisplayName("CT-07-09: 08:15–18:00 e 08:00–17:45 dão 422 (fora da grade); 08:30–18:30 aceito e os livres seguem o relógio")
    void ct0709Grid() {
        assertValidation(putDay("TUE", "08:15", "18:00"), "days[0].windows[0].start");
        assertValidation(putDay("TUE", "08:00", "17:45"), "days[0].windows[0].end");
        assertValidation(putDay("TUE", "09:01", "12:00"), "days[0].windows[0].start");
        Res second = send(req(HttpMethod.PUT, "/barbershops/" + w.shopA + "/professionals/" + w.p1 + "/working-hours").token(w.tGA)
                .body(map("days", List.of(map("weekday", "TUE", "windows", List.of(
                        map("start", "08:00", "end", "12:00"), map("start", "13:00", "end", "17:10")))))));
        assertValidation(second, "days[0].windows[1].end");
        assertOldHoursKept();

        assertThat(putDay("TUE", "08:30", "18:30").status()).isEqualTo(200);
        List<String> corte = slots(w.shopA, w.corte, w.p1, "2026-10-13");
        assertThat(corte).first().isEqualTo("08:30");
        assertThat(corte).contains("09:00", "09:30");
        assertThat(corte).last().isEqualTo("18:00");
    }

    @Test
    @DisplayName("CT-02-21: expediente com fim 00:00 é recusado e o de 21:00 fica; o bloqueio 23:30–00:00 continua aceito")
    void ct0221MidnightOnlyForBlocks() {
        assertThat(putDay("FRI", "08:00", "21:00").status()).isEqualTo(200);
        Res midnight = putDay("FRI", "08:00", "00:00");
        assertValidation(midnight, "days[0].windows[0].end");
        JsonNode fri = getHours(w.shopA, w.p1).body().get("days").get(0);
        assertThat(fri.get("weekday").asText()).isEqualTo("FRI");
        assertThat(fri.get("windows").get(0).get("end").asText()).isEqualTo("21:00");
        assertThat(count("SELECT count(*) FROM working_hours_windows WHERE end_minute = 1440")).isZero();
        // BlockService fica como está: fim às 00:00 do dia seguinte conta como fim da sexta.
        Res block = block(w.tP1, w.shopA, w.p1, "2026-10-09T23:30", "2026-10-10T00:00");
        assertThat(block.status()).as(block.toString()).isEqualTo(201);
    }

    @Test
    @DisplayName("CT-07-07: profissional que mexe no expediente leva 403 antes de qualquer 422")
    void ct0707ForbiddenBeforeValidation() {
        assertThat(putHours(w.tP1, w.shopA, w.p1, "MON", "07:00", "00:00").status()).isEqualTo(403);
    }

    @Test
    @DisplayName("CT-01-17 (servidor): o turno vem pelo início; Corte + Barba 11:30–12:30 é manhã, 12:00 tarde, 18:00 noite")
    void ct0117PeriodByStart() {
        assertThat(putAllDays(w.tGA, w.shopA, w.p1, "08:00", "21:00").status()).isEqualTo(200);
        Res r = availability(w.shopA, w.combo, w.p1, "2026-10-08");
        assertThat(r.status()).isEqualTo(200);
        Map<String, String> periodByTime = new LinkedHashMap<>();
        for (JsonNode s : r.body().get("slots")) {
            periodByTime.put(s.get("startAt").asText().substring(11, 16), s.get("period").asText());
        }
        assertThat(periodByTime.keySet()).first().isEqualTo("08:00");
        assertThat(periodByTime.keySet()).last().isEqualTo("20:00");
        assertThat(periodByTime).containsEntry("11:30", "MORNING")
                .containsEntry("12:00", "AFTERNOON")
                .containsEntry("17:30", "AFTERNOON")
                .containsEntry("18:00", "EVENING")
                .containsEntry("20:00", "EVENING");
    }

    // ------------------------------------------------------------------ 3: duração em múltiplos de 30

    @Test
    @DisplayName("CT-10-07: criar serviço com 45, 15, 0, -30 ou 510 min dá 422 em durationMinutes")
    void ct1007CreateRejectsNonMultipleOf30() {
        for (int minutes : new int[] {45, 15, 0, -30, 510, 29, 31}) {
            assertValidation(createService(minutes), "durationMinutes");
        }
        assertThat(count("SELECT count(*) FROM services WHERE name LIKE 'Serviço %'")).isZero();
    }

    @Test
    @DisplayName("CT-10-07: mudar a duração para 45 dá 422 e o serviço fica como estava; 90 é aceito")
    void ct1007PatchRejectsNonMultipleOf30() {
        assertValidation(patchService(w.barba, 45), "durationMinutes");
        assertThat(durationInDb(w.barba)).isEqualTo(30);
        assertValidation(patchService(w.barba, 5), "durationMinutes");
        Res ok = patchService(w.barba, 90);
        assertThat(ok.status()).as(ok.toString()).isEqualTo(200);
        assertThat(durationInDb(w.barba)).isEqualTo(90);
    }

    @Test
    @DisplayName("CT-10-07: o banco também recusa duração fora da grade de 30 (CHECK ck_services_duration_grid_30)")
    void ct1007DatabaseCheck() {
        for (int minutes : new int[] {45, 5, 510}) {
            assertThatThrownBy(() -> w.service(w.shopA, "Direto " + minutes, minutes, 1000))
                    .as("duração " + minutes).isInstanceOf(DataIntegrityViolationException.class)
                    .hasMessageContaining("ck_services_duration_grid_30");
        }
        assertThat(w.service(w.shopA, "Direto 120", 120, 1000)).isNotNull();
    }

    @Test
    @DisplayName("CT-10-10: serviços de 30, 60 e 90 aceitos; o de 90 vai de 08:00 a 19:30 e ocupa 3 horários")
    void ct1010NinetyMinutes() {
        assertThat(putAllDays(w.tGA, w.shopA, w.p1, "08:00", "21:00").status()).isEqualTo(200);
        UUID s90 = null;
        for (int minutes : new int[] {30, 60, 90, 480}) {
            Res r = createService(minutes);
            assertThat(r.status()).as(r.toString()).isEqualTo(201);
            assertThat(r.body().get("durationMinutes").asInt()).isEqualTo(minutes);
            if (minutes == 90) {
                s90 = r.id();
            }
        }
        List<String> free90 = slots(w.shopA, s90, w.p1, "2026-10-08");
        assertThat(free90).first().isEqualTo("08:00");
        assertThat(free90).last().isEqualTo("19:30");
        assertThat(free90).doesNotContain("20:00");
        Res booked = houseBook(s90, w.p1, "2026-10-08T10:00");
        assertThat(booked.status()).as(booked.toString()).isEqualTo(201);
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).doesNotContain("10:00", "10:30", "11:00").contains("09:30", "11:30");
    }

    // ------------------------------------------------------------------ 5: profissional em Clientes

    @Test
    @DisplayName("CT-17-07: profissional que não é gerente busca, abre e cadastra cliente")
    void ct1707ProfessionalSearchesAndCreates() {
        Res created = createClient(w.tP1, w.shopA, "João Almeida", "(11) 98765-4321");
        assertThat(created.status()).as(created.toString()).isEqualTo(201);
        Res search = get("/barbershops/" + w.shopA + "/clients?q=joao", w.tP1);
        assertThat(search.status()).isEqualTo(200);
        assertThat(search.body()).hasSize(1);
        assertThat(search.body().get(0).get("id").asText()).isEqualTo(created.id().toString());
        assertThat(get("/barbershops/" + w.shopA + "/clients/" + created.id(), w.tP1).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("CT-17-34: profissional leva 403 ao editar a ficha criada pelo gerente e a que ele mesmo criou; nada muda; G-A edita as duas")
    void ct1734EditIsManagerOnly() {
        UUID byManager = createClient(w.tGA, w.shopA, "João Almeida", "11987654321").id();
        UUID byPro = createClient(w.tP1, w.shopA, "Ana Souza", "21912345678").id();
        Object change = map("name", "Outro Nome", "phone", "11 3456-7890", "email", "outro@x.test");
        for (UUID id : new UUID[] {byManager, byPro}) {
            Res r = patchClient(w.tP1, w.shopA, id, change);
            assertThat(r.status()).as(r.toString()).isEqualTo(403);
            assertThat(r.code()).isEqualTo("FORBIDDEN");
            // 403 vem antes do 422 (varredura CT-00-24).
            assertThat(patchClient(w.tP1, w.shopA, id, map("name", "")).status()).isEqualTo(403);
        }
        assertThat(count("SELECT count(*) FROM client_profiles WHERE name = 'Outro Nome' OR email IS NOT NULL")).isZero();
        assertThat(count("SELECT count(*) FROM clients WHERE phone = '551134567890'")).isZero();
        Res a = patchClient(w.tGA, w.shopA, byManager, map("name", "João A.", "email", "joao@x.test"));
        Res b = patchClient(w.tGA, w.shopA, byPro, map("name", "Ana S."));
        assertThat(a.status()).as(a.toString()).isEqualTo(200);
        assertThat(b.status()).as(b.toString()).isEqualTo(200);
        // Gerente que também é profissional edita normalmente.
        assertThat(patchClient(w.tGP, w.shopA, byPro, map("name", "Ana Souza")).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("CT-17-35: na A, P1 busca 200, cadastra 201, edita 403 e libera 403; G-A tudo aceito; G-B 404 em tudo")
    void ct1735RoleMatrix() {
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        UUID t1 = db.sql("""
                        SELECT p.id FROM client_profiles p JOIN clients c ON c.id = p.client_id
                         WHERE p.barbershop_id = :b AND c.phone = :ph
                        """).param("b", w.shopA).param("ph", T1).query(UUID.class).single();
        String base = "/barbershops/" + w.shopA + "/clients";
        String release = base + "/" + t1 + "/release-device";

        assertThat(get(base + "?q=cliente", w.tP1).status()).isEqualTo(200);
        assertThat(createClient(w.tP1, w.shopA, "Novo P1", "11911112222").status()).isEqualTo(201);
        assertThat(patchClient(w.tP1, w.shopA, t1, map("name", "Mudou")).status()).isEqualTo(403);
        assertThat(send(req(HttpMethod.POST, release).token(w.tP1)).status()).isEqualTo(403);

        assertThat(get(base + "?q=cliente", w.tGB).status()).isEqualTo(404);
        assertThat(createClient(w.tGB, w.shopA, "Novo GB", "11933334444").status()).isEqualTo(404);
        assertThat(patchClient(w.tGB, w.shopA, t1, map("name", "Mudou")).status()).isEqualTo(404);
        assertThat(send(req(HttpMethod.POST, release).token(w.tGB)).status()).isEqualTo(404);

        assertThat(get(base + "?q=cliente", w.tGA).status()).isEqualTo(200);
        assertThat(createClient(w.tGA, w.shopA, "Novo GA", "11955556666").status()).isEqualTo(201);
        assertThat(patchClient(w.tGA, w.shopA, t1, map("name", "Cliente Editado")).status()).isEqualTo(200);
        assertThat(send(req(HttpMethod.POST, release).token(w.tGA)).status()).isEqualTo(204);
    }

    // ------------------------------------------------------------------ 6: profissional desativado (por barbearia)

    @Test
    @DisplayName("CT-10-11: desativado (só na A) faz login com a senha certa e leva o mesmo 401 da senha errada, sem token")
    void ct1011DeactivatedLoginIs401() {
        assertThat(login("p1@a.test", World.PASSWORD).status()).isEqualTo(200);
        assertThat(setActive(w.tGA, w.shopA, w.p1, false).status()).isEqualTo(200);
        Res deactivated = login("p1@a.test", World.PASSWORD);
        Res wrongPassword = login("p1@a.test", "senha-errada-123");
        Res unknown = login("ninguem@a.test", World.PASSWORD);
        assertThat(deactivated.status()).isEqualTo(401);
        assertThat(wrongPassword.status()).isEqualTo(401);
        assertThat(deactivated.body().get("accessToken")).isNull();
        assertThat(deactivated.body()).isEqualTo(wrongPassword.body()).isEqualTo(unknown.body());
    }

    @Test
    @DisplayName("CT-10-12: token emitido antes da desativação dá 401 na hora em /auth/me, na própria agenda e no bloquear; nada é criado")
    void ct1012OldTokenIs401() {
        assertThat(get("/auth/me", w.tP1).status()).isEqualTo(200);
        assertThat(setActive(w.tGA, w.shopA, w.p1, false).status()).isEqualTo(200);
        Res me = get("/auth/me", w.tP1);
        assertThat(me.status()).isEqualTo(401);
        assertThat(me.code()).isEqualTo("UNAUTHORIZED");
        assertThat(get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08&professionalId=" + w.p1, w.tP1).status())
                .isEqualTo(401);
        assertThat(block(w.tP1, w.shopA, w.p1, "2026-10-08T10:00", "2026-10-08T10:30").status()).isEqualTo(401);
        assertThat(count("SELECT count(*) FROM blocks")).isZero();
        // Os outros continuam.
        assertThat(get("/auth/me", w.tP2).status()).isEqualTo(200);
        assertThat(get("/auth/me", w.tGA).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("CT-10-12: a checagem é em todo pedido (desativar direto no banco também derruba o token, e reativar devolve)")
    void ct1012CheckedOnEveryRequest() {
        db.sql("UPDATE professionals SET active = false, deactivated_at = now() WHERE id = :p").param("p", w.p2).update();
        assertThat(get("/auth/me", w.tP2).status()).isEqualTo(401);
        db.sql("UPDATE professionals SET active = true, deactivated_at = NULL WHERE id = :p").param("p", w.p2).update();
        assertThat(get("/auth/me", w.tP2).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("CT-10-13: P1 não reativa (403); G-A reativa pelo PATCH, o profissional volta a entrar e volta aos livres")
    void ct1013Reactivate() {
        assertThat(setActive(w.tGA, w.shopA, w.p2, false).status()).isEqualTo(200);
        Res list = get("/barbershops/" + w.shopA + "/professionals", w.tGA);
        boolean listedInactive = false;
        for (JsonNode p : list.body()) {
            if (p.get("id").asText().equals(w.p2.toString())) {
                listedInactive = !p.get("active").asBoolean();
            }
        }
        assertThat(listedInactive).as("o gerente ainda vê o desativado para reativar").isTrue();
        assertThat(availability(w.shopA, w.corte, w.p2, "2026-10-08").status()).isEqualTo(404);

        assertThat(setActive(w.tP1, w.shopA, w.p2, true).status()).isEqualTo(403);
        assertThat(isActive(w.p2)).isFalse();

        Res back = setActive(w.tGA, w.shopA, w.p2, true);
        assertThat(back.status()).as(back.toString()).isEqualTo(200);
        assertThat(back.body().get("active").asBoolean()).isTrue();
        Res session = login("p2@a.test", World.PASSWORD);
        assertThat(session.status()).isEqualTo(200);
        String fresh = session.body().get("accessToken").asText();
        assertThat(get("/auth/me", fresh).status()).isEqualTo(200);
        assertThat(get("/barbershops/" + w.shopA + "/agenda?date=2026-10-08&professionalId=" + w.p2, fresh).status())
                .isEqualTo(200);
        assertThat(slots(w.shopA, w.corte, w.p2, "2026-10-08")).isNotEmpty();
        // Sem revogação: o token antigo (ainda no prazo) também volta a valer.
        assertThat(get("/auth/me", w.tP2).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("CT-10-04 / CT-10-09: o histórico do desativado continua gravado (é o que o caixa do gerente soma)")
    void ct1004HistoryStays() {
        UUID done = insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-06T10:00", 30, "COMPLETED");
        assertThat(setActive(w.tGA, w.shopA, w.p1, false).status()).isEqualTo(200);
        assertThat(statusInDb(done)).isEqualTo("COMPLETED");
        assertThat(count("SELECT count(*) FROM bookings WHERE id = '" + done + "' AND professional_id = '" + w.p1
                + "' AND professional_cents = 600 AND shop_cents = 400")).isEqualTo(1);
        assertThat(isActive(w.p1)).isFalse();
    }

    @Test
    @DisplayName("PO 08/10, desativação por barbearia: PX desativado na B leva 403 na B e continua 200 na A com o mesmo token; reativar devolve a B")
    void deactivationIsPerBarbershop() {
        assertThat(get("/barbershops/" + w.shopB + "/clients", w.tPX).status()).isEqualTo(200);
        assertThat(setActive(w.tGB, w.shopB, w.px, false).status()).isEqualTo(200);

        Res inB = get("/barbershops/" + w.shopB + "/clients", w.tPX);
        assertThat(inB.status()).isEqualTo(403);
        assertThat(inB.code()).isEqualTo("FORBIDDEN");
        Res otherForbidden = send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/services").token(w.tP1)
                .body(map("name", "X", "durationMinutes", 30, "priceCents", 100)));
        assertThat(inB.body()).isEqualTo(otherForbidden.body()); // mesmo corpo das outras recusas de papel
        assertThat(get("/barbershops/" + w.shopB + "/agenda?date=2026-10-08&professionalId=" + w.px, w.tPX).status())
                .isEqualTo(403);
        assertThat(block(w.tPX, w.shopB, w.px, "2026-10-08T10:00", "2026-10-08T10:30").status()).isEqualTo(403);

        assertThat(get("/barbershops/" + w.shopA + "/clients", w.tPX).status()).isEqualTo(200);
        Res me = get("/auth/me", w.tPX);
        assertThat(me.status()).isEqualTo(200);
        assertThat(me.body().get("memberships")).hasSize(1);
        assertThat(me.body().get("memberships").get(0).get("barbershopId").asText()).isEqualTo(w.shopA.toString());
        assertThat(login("px@test", World.PASSWORD).status()).isEqualTo(200);
        assertThat(count("SELECT count(*) FROM blocks")).isZero();

        assertThat(setActive(w.tGB, w.shopB, w.px, true).status()).isEqualTo(200);
        assertThat(get("/barbershops/" + w.shopB + "/clients", w.tPX).status()).isEqualTo(200);
        assertThat(get("/auth/me", w.tPX).body().get("memberships")).hasSize(2);
    }

    @Test
    @DisplayName("PO 08/10: quem é gerente e profissional na A não perde o acesso quando o profissional é desativado")
    void managerKeepsAccessWhenProfessionalDeactivated() {
        assertThat(setActive(w.tGA, w.shopA, w.gp, false).status()).isEqualTo(200);
        assertThat(get("/auth/me", w.tGP).status()).isEqualTo(200);
        assertThat(get("/barbershops/" + w.shopA + "/professionals", w.tGP).status()).isEqualTo(200);
        assertThat(login("gp@a.test", World.PASSWORD).status()).isEqualTo(200);
    }
}
