package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.common.Money;
import br.com.cortaaqui.support.DomainTest;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpMethod;

/**
 * Caixa do mês (história 8). Agora = 07/10/2026 09:00 (Brasília); a JVM dos testes roda em UTC.
 * P1 usa o padrão 60/40, P2 tem 70/30 (profissional/casa). Corte R$ 40, Barba R$ 30, Combo R$ 65.
 */
class CashIT extends DomainTest {

    // ------------------------------------------------------------------ atalhos

    private Res cash(String token, UUID shop, String month) {
        return get("/barbershops/" + shop + "/cash?month=" + month, token);
    }

    private Res proCash(String token, UUID shop, UUID pro, String month) {
        return get("/barbershops/" + shop + "/cash/professionals/" + pro + "?month=" + month, token);
    }

    private Res complete(UUID bookingId) {
        Res r = status(w.tGA, w.shopA, bookingId, "COMPLETED");
        assertThat(r.status()).as("concluir: %s", r).isEqualTo(200);
        return r;
    }

    private UUID book(UUID service, UUID pro, String startLocal) {
        Res r = houseBook(service, pro, startLocal);
        assertThat(r.status()).as("marcar: %s", r).isEqualTo(201);
        return r.id();
    }

    private static JsonNode line(Res cash, UUID pro) {
        for (JsonNode l : cash.body().get("byProfessional")) {
            if (l.get("professional").get("id").asText().equals(pro.toString())) {
                return l;
            }
        }
        return null;
    }

    private static long n(JsonNode node, String field) {
        assertThat(node.has(field)).as("campo %s em %s", field, node).isTrue();
        return node.get(field).asLong();
    }

    /** Totais no formato [completedCount, grossCents, shopCents, professionalCents]. */
    private static void assertTotals(JsonNode t, long count, long gross, long shop, long professional) {
        assertThat(n(t, "completedCount")).isEqualTo(count);
        assertThat(n(t, "grossCents")).isEqualTo(gross);
        assertThat(n(t, "shopCents")).isEqualTo(shop);
        assertThat(n(t, "professionalCents")).isEqualTo(professional);
    }

    /** Visão de profissional: o campo shopCents não vem (nem null, nem zero). */
    private static void assertOwnTotals(JsonNode t, long count, long gross, long professional) {
        assertThat(n(t, "completedCount")).isEqualTo(count);
        assertThat(n(t, "grossCents")).isEqualTo(gross);
        assertThat(n(t, "professionalCents")).isEqualTo(professional);
        assertThat(t.has("shopCents")).as("shopCents não pode vir: %s", t).isFalse();
    }

    /** Casa + soma dos profissionais = bruto, centavo por centavo, no total e em cada linha. */
    private static void assertSumsToTheCent(Res cash) {
        JsonNode totals = cash.body().get("totals");
        long gross = 0;
        long shop = 0;
        long professionals = 0;
        for (JsonNode l : cash.body().get("byProfessional")) {
            assertThat(n(l, "shopCents") + n(l, "professionalCents")).isEqualTo(n(l, "grossCents"));
            gross += n(l, "grossCents");
            shop += n(l, "shopCents");
            professionals += n(l, "professionalCents");
        }
        assertThat(n(totals, "grossCents")).isEqualTo(gross);
        assertThat(n(totals, "shopCents")).isEqualTo(shop);
        assertThat(n(totals, "professionalCents")).isEqualTo(professionals);
        assertThat(n(totals, "shopCents") + n(totals, "professionalCents")).isEqualTo(n(totals, "grossCents"));
    }

    /**
     * Concluído gravado direto no banco, com a divisão calculada pelo mesmo {@link Money#split}
     * da conclusão. Serve para horários fora do expediente de teste (virada do mês).
     */
    private UUID insertCompleted(UUID shop, UUID pro, UUID service, String startLocal, int minutes, int priceCents, int pct,
                                 String source) {
        LocalDateTime start = LocalDateTime.parse(startLocal);
        Money.Split s = Money.split(priceCents, pct);
        return db.sql("""
                        INSERT INTO bookings (barbershop_id, professional_id, service_id, client_profile_id, source, status,
                                              start_at, end_at, service_name, duration_minutes, price_cents,
                                              professional_percent, shop_percent, professional_cents, shop_cents,
                                              completed_at, idempotency_key, request_fingerprint)
                        VALUES (:b, :p, :s, :cp, :src, 'COMPLETED', CAST(:start AS timestamptz), CAST(:end AS timestamptz),
                                'X', :d, :price, :pp, :sp, :pc, :sc, CAST(:end AS timestamptz), gen_random_uuid(), repeat('0', 64))
                        RETURNING id
                        """)
                .param("b", shop).param("p", pro).param("s", service).param("cp", walkInProfile(shop)).param("src", source)
                .param("start", sp(startLocal)).param("end", sp(start.plusMinutes(minutes).toString())).param("d", minutes)
                .param("price", priceCents).param("pp", s.professionalPercent()).param("sp", s.shopPercent())
                .param("pc", s.professionalCents()).param("sc", s.shopCents())
                .query(UUID.class).single();
    }

    /**
     * Base do CT-08-03 (plano da QA), toda em 07/10:
     * concluídos P1 Corte 40 + Combo 65 + balcão Barba 30 (sem telefone), P2 Barba 30;
     * mais 1 falta de P1, 1 cancelado de P2 e 1 agendado de P1 que ninguém concluiu (nenhum dos três entra).
     */
    private void baseCt0803() {
        UUID c1 = book(w.corte, w.p1, "2026-10-07T10:00");
        UUID c2 = book(w.combo, w.p1, "2026-10-07T11:00");
        UUID c3 = book(w.barba, w.p2, "2026-10-07T10:00");
        Res counter = staffBook(w.tGA, w.shopA, w.barba, w.p1, "2026-10-07T14:00", "COUNTER", "Seu Zé", null);
        assertThat(counter.status()).as("balcão: %s", counter).isEqualTo(201);
        UUID noShow = book(w.corte, w.p1, "2026-10-07T12:00");
        UUID canceled = book(w.corte, w.p2, "2026-10-07T12:00");
        book(w.corte, w.p1, "2026-10-07T16:00"); // fica SCHEDULED
        clock.setSp("2026-10-07T18:00:00");
        complete(c1);
        complete(c2);
        complete(c3);
        complete(counter.id());
        assertThat(status(w.tGA, w.shopA, noShow, "NO_SHOW").status()).isEqualTo(200);
        assertThat(status(w.tGA, w.shopA, canceled, "CANCELED").status()).isEqualTo(200);
    }

    // ------------------------------------------------------------------ gerente

    @Test
    @DisplayName("CT-08-01/02/03/11/15 gerente: total, linhas e casa; falta, cancelado e agendado não entram; balcão entra")
    void managerSeesEverything() {
        baseCt0803();
        Res r = cash(w.tGA, w.shopA, "2026-10");
        assertThat(r.status()).isEqualTo(200);
        assertThat(r.body().get("month").asText()).isEqualTo("2026-10");
        // total R$ 165,00; P1 R$ 81,00; P2 R$ 21,00; casa R$ 63,00 (54,00 de P1 + 9,00 de P2)
        assertTotals(r.body().get("totals"), 4, 16500, 6300, 10200);
        assertTotals(line(r, w.p1), 3, 13500, 5400, 8100);
        assertTotals(line(r, w.p2), 1, 3000, 900, 2100);
        assertTotals(line(r, w.gp), 0, 0, 0, 0); // ativo sem concluído aparece zerado
        assertThat(r.body().get("byProfessional")).hasSize(3);
        assertSumsToTheCent(r);

        // GP é gerente e profissional: vê tudo igual, não só a linha dele.
        Res gp = cash(w.tGP, w.shopA, "2026-10");
        assertThat(gp.status()).isEqualTo(200);
        assertThat(gp.body()).isEqualTo(r.body());

        // Rotas por profissional: gerente pede qualquer um e recebe shopCents.
        Res p1 = proCash(w.tGA, w.shopA, w.p1, "2026-10");
        assertThat(p1.status()).isEqualTo(200);
        assertTotals(p1.body().get("totals"), 3, 13500, 5400, 8100);
        assertThat(p1.body().get("bookings")).hasSize(3)
                .allSatisfy(b -> assertThat(b.get("status").asText()).isEqualTo("COMPLETED"))
                .allSatisfy(b -> assertThat(b.get("professional").get("id").asText()).isEqualTo(w.p1.toString()))
                .allSatisfy(b -> assertThat(b.get("shopPercent").asInt()).isEqualTo(40));
        assertThat(p1.body().get("bookings").findValuesAsText("source")).contains("COUNTER");
        Res p2 = proCash(w.tGA, w.shopA, w.p2, "2026-10");
        assertThat(p2.status()).isEqualTo(200);
        assertTotals(p2.body().get("totals"), 1, 3000, 900, 2100);
    }

    // ------------------------------------------------------------------ profissional

    @Test
    @DisplayName("CT-08-09/13/14 profissional: 200 só com a própria linha, totals = linha, sem shopCents")
    void professionalSeesOnlyOwnRow() {
        baseCt0803();
        Res r = cash(w.tP1, w.shopA, "2026-10");
        assertThat(r.status()).isEqualTo(200);
        assertThat(r.body().get("byProfessional")).hasSize(1);
        JsonNode own = line(r, w.p1);
        assertThat(own).isNotNull();
        assertOwnTotals(own, 3, 13500, 8100);
        assertOwnTotals(r.body().get("totals"), 3, 13500, 8100);
        // Nada da casa nem de P2 em lugar nenhum da resposta.
        String raw = r.body().toString();
        assertThat(raw).doesNotContain("shopCents").doesNotContain(w.p2.toString()).doesNotContain(w.gp.toString());
        assertThat(r.body().get("totals").get("grossCents").asLong()).isNotEqualTo(16500); // nem o bruto da barbearia

        Res mine = proCash(w.tP1, w.shopA, w.p1, "2026-10");
        assertThat(mine.status()).isEqualTo(200);
        assertOwnTotals(mine.body().get("totals"), 3, 13500, 8100);
        assertThat(mine.body().get("bookings")).hasSize(3)
                .allSatisfy(b -> assertThat(b.get("professional").get("id").asText()).isEqualTo(w.p1.toString()))
                .allSatisfy(b -> assertThat(b.has("shopPercent")).isFalse());
        assertThat(mine.body().toString()).doesNotContain("shopCents");
    }

    @Test
    @DisplayName("CT-08-10 / CT-00-15 profissional pedindo o ganho de outro: 403 sem nenhum valor")
    void professionalCannotSeeOthers() {
        baseCt0803();
        Res r = proCash(w.tP1, w.shopA, w.p2, "2026-10");
        assertThat(r.status()).isEqualTo(403);
        assertThat(r.code()).isEqualTo("FORBIDDEN");
        assertThat(r.body().toString()).doesNotContain("grossCents").doesNotContain("bookings");
        // PX é gerente na A, mas só profissional na B: na B ele não vê o PB1.
        assertThat(proCash(w.tPX, w.shopB, w.pb1, "2026-10").status()).isEqualTo(403);
        assertThat(proCash(w.tPX, w.shopB, w.px, "2026-10").status()).isEqualTo(200);
    }

    @Test
    @DisplayName("CT-08-13 profissional sem concluído no mês: 200 com a linha dele zerada, sem shopCents")
    void professionalWithNothingGetsZeroRow() {
        baseCt0803();
        Res r = cash(w.tP2, w.shopA, "2026-09");
        assertThat(r.status()).isEqualTo(200);
        assertThat(r.body().get("byProfessional")).hasSize(1);
        assertOwnTotals(line(r, w.p2), 0, 0, 0);
        assertOwnTotals(r.body().get("totals"), 0, 0, 0);
        Res mine = proCash(w.tP2, w.shopA, w.p2, "2026-09");
        assertThat(mine.status()).isEqualTo(200);
        assertThat(mine.body().get("bookings")).isEmpty();
        assertOwnTotals(mine.body().get("totals"), 0, 0, 0);
    }

    // ------------------------------------------------------------------ barbearia

    @Test
    @DisplayName("CT-08-06 / regra geral: outra barbearia dá 404; caixa da A não traz nada da B")
    void otherBarbershop() {
        UUID a = book(w.corte, w.p1, "2026-10-07T10:00");
        Res b = staffBook(w.tGB, w.shopB, w.corteB, w.pb1, "2026-10-07T10:00", "STAFF", "Cliente B", "11912345679");
        clock.setSp("2026-10-07T11:00:00");
        complete(a);
        assertThat(status(w.tGB, w.shopB, b.id(), "COMPLETED").status()).isEqualTo(200);

        Res cashA = cash(w.tGA, w.shopA, "2026-10");
        assertTotals(cashA.body().get("totals"), 1, 4000, 1600, 2400);
        assertThat(cashA.body().toString()).doesNotContain(w.pb1.toString());
        Res cashB = cash(w.tGB, w.shopB, "2026-10");
        assertTotals(cashB.body().get("totals"), 1, 5000, 2000, 3000);

        // G-B (só da B) na A: 404, sem revelar nada.
        assertThat(cash(w.tGB, w.shopA, "2026-10").status()).isEqualTo(404);
        assertThat(proCash(w.tGB, w.shopA, w.p1, "2026-10").status()).isEqualTo(404);
        assertThat(cash(w.tPB1, w.shopA, "2026-10").status()).isEqualTo(404);
        // Mesmo com mês inválido, quem não é da barbearia recebe 404 primeiro.
        assertThat(cash(w.tGB, w.shopA, "2026-13").status()).isEqualTo(404);
        // Gerente da A pedindo profissional da B pela rota da A: 404.
        assertThat(proCash(w.tGA, w.shopA, w.pb1, "2026-10").status()).isEqualTo(404);
        assertThat(proCash(w.tGA, w.shopA, UUID.randomUUID(), "2026-10").status()).isEqualTo(404);
        // Sem token: 401.
        assertThat(send(req(HttpMethod.GET, "/barbershops/" + w.shopA + "/cash?month=2026-10")).status()).isEqualTo(401);
    }

    // ------------------------------------------------------------------ mês e fuso

    @Test
    @DisplayName("CT-08-07 virada do mês no fuso de São Paulo (JVM em UTC): 31/10 23:30 é outubro; 01/11 00:00 é novembro")
    void monthBoundaryInSaoPaulo() {
        insertCompleted(w.shopA, w.p1, w.corte, "2026-09-30T23:30", 30, 1000, 60, "STAFF"); // = 01/10 02:30 UTC
        insertCompleted(w.shopA, w.p1, w.corte, "2026-10-01T00:00", 30, 2000, 60, "STAFF");
        insertCompleted(w.shopA, w.p1, w.corte, "2026-10-31T23:30", 30, 4000, 60, "STAFF"); // = 01/11 02:30 UTC
        insertCompleted(w.shopA, w.p1, w.corte, "2026-11-01T00:00", 30, 8000, 60, "STAFF");

        Res sep = cash(w.tGA, w.shopA, "2026-09");
        Res oct = cash(w.tGA, w.shopA, "2026-10");
        Res nov = cash(w.tGA, w.shopA, "2026-11");
        assertThat(n(sep.body().get("totals"), "grossCents")).isEqualTo(1000);
        assertThat(n(oct.body().get("totals"), "grossCents")).isEqualTo(6000);
        assertThat(n(oct.body().get("totals"), "completedCount")).isEqualTo(2);
        assertThat(n(nov.body().get("totals"), "grossCents")).isEqualTo(8000);

        List<String> octStarts = proCash(w.tGA, w.shopA, w.p1, "2026-10").body().get("bookings").findValuesAsText("startAt");
        assertThat(octStarts).containsExactly("2026-10-01T00:00:00-03:00", "2026-10-31T23:30:00-03:00");
    }

    @Test
    @DisplayName("CT-08-08 / CT-08-12 conta o mês do atendimento, não o da conclusão (31/10 18:00 concluído em 01/11)")
    void monthOfStartNotOfCompletion() {
        clock.setSp("2026-10-25T09:00:00");
        w.tGA = auth.createSession(w.uGA); // o token da Casa vale 7 dias
        UUID id = book(w.corte, w.p1, "2026-10-31T18:00");
        assertThat(n(cash(w.tGA, w.shopA, "2026-10").body().get("totals"), "grossCents")).isZero();
        clock.setSp("2026-11-01T09:00:00");
        w.tGA = auth.createSession(w.uGA);
        complete(id);
        assertThat(count("SELECT count(*) FROM bookings WHERE completed_at >= '2026-11-01T00:00:00-03:00'")).isEqualTo(1);
        assertTotals(cash(w.tGA, w.shopA, "2026-10").body().get("totals"), 1, 4000, 1600, 2400);
        assertTotals(cash(w.tGA, w.shopA, "2026-11").body().get("totals"), 0, 0, 0, 0);
    }

    @ParameterizedTest(name = "month={0}")
    @ValueSource(strings = {"2026-13", "2026-00", "2026-1", "26-10", "2026-10-01", "outubro", "2026/10", ""})
    @DisplayName("Mês fora do formato AAAA-MM: 422 VALIDATION_ERROR no campo month")
    void invalidMonth(String month) {
        for (Res r : List.of(cash(w.tGA, w.shopA, month), proCash(w.tGA, w.shopA, w.p1, month),
                cash(w.tP1, w.shopA, month))) {
            assertThat(r.status()).isEqualTo(422);
            assertThat(r.code()).isEqualTo("VALIDATION_ERROR");
            assertThat(r.body().get("fields").get(0).get("field").asText()).isEqualTo("month");
        }
    }

    @Test
    @DisplayName("Sem o parâmetro month: 422 VALIDATION_ERROR")
    void missingMonth() {
        Res r = get("/barbershops/" + w.shopA + "/cash", w.tGA);
        assertThat(r.status()).isEqualTo(422);
        assertThat(r.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(get("/barbershops/" + w.shopA + "/cash/professionals/" + w.p1, w.tGA).status()).isEqualTo(422);
    }

    // ------------------------------------------------------------------ dinheiro

    @Test
    @DisplayName("CT-20-08 / CT-20-09 R$ 33,33 concluído pela API: 50% grava 16,67 / 16,66, 60% grava 20,00 / 13,33 (e 70% 23,33 / 10,00); o caixa mostra o mesmo, sem recalcular")
    void roundingPerBookingThroughApi() {
        UUID avulso = w.service(w.shopA, "Avulso", 30, 3333);
        db.sql("UPDATE professionals SET professional_percent = 50 WHERE id = :p").param("p", w.p1).update();
        UUID a = book(avulso, w.p1, "2026-10-07T10:00");
        UUID b = book(avulso, w.p2, "2026-10-07T10:00"); // 70%: 2333,1 -> 2333; casa 1000
        UUID c = book(avulso, w.gp, "2026-10-07T10:00"); // padrão 60%: 1999,8 -> 2000; casa 1333
        clock.setSp("2026-10-07T10:30:00");
        complete(a);
        complete(b);
        complete(c);
        Map<String, Object> row = db.sql("SELECT professional_cents, shop_cents FROM bookings WHERE id = :id")
                .param("id", a).query().singleRow();
        assertThat(row).containsEntry("professional_cents", 1667).containsEntry("shop_cents", 1666);

        Res r = cash(w.tGA, w.shopA, "2026-10");
        assertTotals(line(r, w.p1), 1, 3333, 1666, 1667);
        assertTotals(line(r, w.p2), 1, 3333, 1000, 2333);
        assertTotals(line(r, w.gp), 1, 3333, 1333, 2000);
        assertTotals(r.body().get("totals"), 3, 9999, 3999, 6000);
        assertSumsToTheCent(r);
    }

    @Test
    @DisplayName("CT-08-05 gerador com 300 concluídos: casa + profissionais = bruto, centavo por centavo, igual ao banco")
    void generatorSumsToTheCent() {
        Random random = new Random(20261008);
        UUID[] pros = {w.p1, w.p2, w.gp};
        LocalDateTime start = LocalDateTime.parse("2026-10-01T00:00");
        long gross = 0;
        long professionals = 0;
        for (int i = 0; i < 300; i++) {
            int price = random.nextInt(50_000) + (random.nextBoolean() ? 1 : 0);
            int pct = random.nextInt(101);
            Money.Split s = Money.split(price, pct);
            gross += price;
            professionals += s.professionalCents();
            insertCompleted(w.shopA, pros[i % 3], w.corte, start.plusMinutes(30L * (i / 3)).toString(), 30, price, pct,
                    i % 5 == 0 ? "COUNTER" : "STAFF");
        }
        Res r = cash(w.tGA, w.shopA, "2026-10");
        assertTotals(r.body().get("totals"), 300, gross, gross - professionals, professionals);
        assertSumsToTheCent(r);
        long dbShop = db.sql("SELECT sum(shop_cents) FROM bookings WHERE status = 'COMPLETED'").query(Long.class).single();
        assertThat(n(r.body().get("totals"), "shopCents")).isEqualTo(dbShop);
        long linesProfessional = 0;
        for (UUID p : pros) {
            Res one = proCash(w.tGA, w.shopA, p, "2026-10");
            assertThat(one.body().get("bookings")).hasSize(100);
            assertThat(one.body().get("totals")).isEqualTo(stripProfessional(line(r, p)));
            linesProfessional += n(one.body().get("totals"), "professionalCents");
        }
        assertThat(linesProfessional).isEqualTo(professionals);
    }

    private JsonNode stripProfessional(JsonNode line) {
        com.fasterxml.jackson.databind.node.ObjectNode copy = line.deepCopy();
        copy.remove("professional");
        return copy;
    }

    // ------------------------------------------------------------------ histórico

    @Test
    @DisplayName("CT-20-05 / CT-20-06 mudar a % depois de concluir não muda o caixa antigo; o próximo concluído usa a nova")
    void percentChangeDoesNotRewritePast() {
        UUID first = book(w.corte, w.p1, "2026-10-07T10:00");
        UUID second = book(w.corte, w.p1, "2026-10-07T11:00");
        clock.setSp("2026-10-07T10:30:00");
        complete(first); // 60/40: 2400 / 1600
        Res before = cash(w.tGA, w.shopA, "2026-10");
        assertTotals(line(before, w.p1), 1, 4000, 1600, 2400);

        Res put = send(req(HttpMethod.PUT, "/barbershops/" + w.shopA + "/commission").token(w.tGA)
                .body(map("default", map("shopPercent", 40, "professionalPercent", 60),
                        "professionals", List.of(map("professionalId", w.p1, "shopPercent", 50, "professionalPercent", 50),
                                map("professionalId", w.p2, "shopPercent", 30, "professionalPercent", 70)))));
        assertThat(put.status()).as("%s", put).isEqualTo(200);

        Res after = cash(w.tGA, w.shopA, "2026-10");
        assertThat(after.body()).isEqualTo(before.body());

        clock.setSp("2026-10-07T11:30:00");
        complete(second); // 50/50: 2000 / 2000
        Res later = cash(w.tGA, w.shopA, "2026-10");
        assertTotals(line(later, w.p1), 2, 8000, 3600, 4400);
        assertThat(db.sql("SELECT professional_percent FROM bookings WHERE id = :id").param("id", first)
                .query(Integer.class).single()).isEqualTo(60);
        assertThat(db.sql("SELECT professional_percent FROM bookings WHERE id = :id").param("id", second)
                .query(Integer.class).single()).isEqualTo(50);
    }

    @Test
    @DisplayName("Profissional desativado continua no caixa do mês em que atendeu; sem atendimento no mês, não aparece")
    void deactivatedProfessionalKeepsHistory() {
        UUID id = book(w.barba, w.p2, "2026-10-07T10:00");
        clock.setSp("2026-10-07T10:30:00");
        complete(id);
        Res off = send(req(HttpMethod.PATCH, "/barbershops/" + w.shopA + "/professionals/" + w.p2).token(w.tGA)
                .body(map("active", false)));
        assertThat(off.status()).as("%s", off).isEqualTo(200);
        assertThat(off.body().get("active").asBoolean()).isFalse();

        Res oct = cash(w.tGA, w.shopA, "2026-10");
        assertTotals(line(oct, w.p2), 1, 3000, 900, 2100);
        assertTotals(oct.body().get("totals"), 1, 3000, 900, 2100);
        Res p2 = proCash(w.tGA, w.shopA, w.p2, "2026-10");
        assertThat(p2.status()).isEqualTo(200);
        assertThat(p2.body().get("bookings")).hasSize(1);

        // P2 só tem a barbearia A. Desativado, o token antigo não entra mais: 401, não 200.
        Res denied = cash(w.tP2, w.shopA, "2026-10");
        assertThat(denied.status()).as("token do desativado: %s", denied).isEqualTo(401);

        Res nov = cash(w.tGA, w.shopA, "2026-11");
        assertThat(line(nov, w.p2)).isNull();
        List<String> names = new ArrayList<>(nov.body().get("byProfessional").findValuesAsText("name"));
        assertThat(names).containsExactly("GP", "P1");
    }
}
