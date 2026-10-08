package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

/** Gerência das % (história 20). Padrão da casa 60/40; P2 tem 70/30 próprio; P1 e GP usam o padrão. */
class CommissionIT extends DomainTest {

    private Res getCommission(String token, UUID shop) {
        return get("/barbershops/" + shop + "/commission", token);
    }

    private Res putCommission(String token, UUID shop, Object body) {
        return send(req(HttpMethod.PUT, "/barbershops/" + shop + "/commission").token(token).body(body));
    }

    private static Map<String, Object> split(int shop, int professional) {
        return map("shopPercent", shop, "professionalPercent", professional);
    }

    private static Map<String, Object> own(UUID pro, Object shop, Object professional) {
        return map("professionalId", pro, "shopPercent", shop, "professionalPercent", professional);
    }

    private Map<String, Object> settings(Map<String, Object> def, List<?> professionals) {
        return map("default", def, "professionals", professionals);
    }

    private Integer pctInDb(UUID pro) {
        return db.sql("SELECT professional_percent FROM professionals WHERE id = :p").param("p", pro)
                .query((rs, i) -> (Integer) rs.getObject(1)).list().get(0);
    }

    private int defaultInDb(UUID shop) {
        return db.sql("SELECT default_professional_percent FROM barbershops WHERE id = :b").param("b", shop)
                .query(Integer.class).single();
    }

    private static JsonNode ownRow(Res r, UUID pro) {
        for (JsonNode p : r.body().get("professionals")) {
            if (p.get("professionalId").asText().equals(pro.toString())) {
                return p;
            }
        }
        return null;
    }

    @Test
    @DisplayName("CT-20-01 padrão 60/40; só quem tem % própria aparece em professionals")
    void defaults() {
        Res r = getCommission(w.tGA, w.shopA);
        assertThat(r.status()).isEqualTo(200);
        assertThat(r.body().get("default").get("professionalPercent").asInt()).isEqualTo(60);
        assertThat(r.body().get("default").get("shopPercent").asInt()).isEqualTo(40);
        assertThat(r.body().get("professionals")).hasSize(1);
        JsonNode p2 = ownRow(r, w.p2);
        assertThat(p2.get("professionalPercent").asInt()).isEqualTo(70);
        assertThat(p2.get("shopPercent").asInt()).isEqualTo(30);
        // Barbearia nova nasce com 60/40.
        UUID novo = w.shop("Nova", "Lapa");
        assertThat(defaultInDb(novo)).isEqualTo(60);
    }

    @Test
    @DisplayName("CT-20-02 70/30, 100/0 e 0/100 são aceitos; PUT troca tudo (quem não veio volta ao padrão)")
    void validSplits() {
        for (int[] s : new int[][] {{30, 70}, {0, 100}, {100, 0}}) {
            Res r = putCommission(w.tGA, w.shopA, settings(split(40, 60), List.of(own(w.p1, s[0], s[1]))));
            assertThat(r.status()).as("%s", r).isEqualTo(200);
            assertThat(ownRow(r, w.p1).get("professionalPercent").asInt()).isEqualTo(s[1]);
            assertThat(ownRow(r, w.p1).get("shopPercent").asInt()).isEqualTo(s[0]);
            assertThat(pctInDb(w.p1)).isEqualTo(s[1]);
            assertThat(getCommission(w.tGA, w.shopA).body()).isEqualTo(r.body());
        }
        // P2 não veio na lista: voltou a usar o padrão (sem linha própria).
        assertThat(pctInDb(w.p2)).isNull();
        // Padrão novo da casa.
        Res r = putCommission(w.tGA, w.shopA, settings(split(45, 55), List.of()));
        assertThat(r.status()).isEqualTo(200);
        assertThat(r.body().get("default").get("professionalPercent").asInt()).isEqualTo(55);
        assertThat(r.body().get("professionals")).isEmpty();
        assertThat(defaultInDb(w.shopA)).isEqualTo(55);
        // A outra barbearia não muda.
        assertThat(defaultInDb(w.shopB)).isEqualTo(60);
    }

    @Test
    @DisplayName("CT-20-03 decimal, fora de 0..100, soma != 100, texto e só um valor: 422 e nada muda no banco")
    void invalidSplits() {
        String p1 = w.p1.toString();
        String def = "{\"shopPercent\":40,\"professionalPercent\":60}";
        Object[][] cases = {
                // corpo, código esperado
                {"{\"default\":" + def + ",\"professionals\":[{\"professionalId\":\"" + p1 + "\",\"shopPercent\":39.5,\"professionalPercent\":60.5}]}", "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(own(w.p1, 101, -1))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(own(w.p1, -1, 101))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(own(w.p1, 40, 70))), "COMMISSION_SUM_INVALID"},
                {settings(split(40, 60), List.of(own(w.p1, 49, 50))), "COMMISSION_SUM_INVALID"},
                {settings(split(40, 70), List.of()), "COMMISSION_SUM_INVALID"},
                {settings(split(40, 60), List.of(own(w.p1, "40", "60"))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(own(w.p1, null, 60))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(map("professionalId", w.p1, "professionalPercent", 60))), "VALIDATION_ERROR"},
                {map("default", map("professionalPercent", 60), "professionals", List.of()), "VALIDATION_ERROR"},
                {map("professionals", List.of()), "VALIDATION_ERROR"},
                {map("default", split(40, 60)), "VALIDATION_ERROR"},
                // profissional de outra barbearia, inexistente, repetido ou sem id
                {settings(split(40, 60), List.of(own(w.pb1, 50, 50))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(own(UUID.randomUUID(), 50, 50))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(own(w.p1, 50, 50), own(w.p1, 30, 70))), "VALIDATION_ERROR"},
                {settings(split(40, 60), List.of(map("shopPercent", 50, "professionalPercent", 50))), "VALIDATION_ERROR"},
                // um item bom e um ruim: nada é gravado
                {settings(split(50, 50), List.of(own(w.p1, 50, 50), own(w.gp, 40, 70))), "COMMISSION_SUM_INVALID"},
        };
        for (Object[] c : cases) {
            Res r = putCommission(w.tGA, w.shopA, c[0]);
            assertThat(r.status()).as("corpo %s -> %s", c[0], r).isEqualTo(422);
            assertThat(r.code()).as("corpo %s -> %s", c[0], r).isEqualTo(c[1]);
            assertThat(pctInDb(w.p1)).isNull();
            assertThat(pctInDb(w.gp)).isNull();
            assertThat(pctInDb(w.p2)).isEqualTo(70);
            assertThat(defaultInDb(w.shopA)).isEqualTo(60);
        }
        Res sum = putCommission(w.tGA, w.shopA, settings(split(40, 60), List.of(own(w.p1, 40, 70))));
        assertThat(sum.body().get("fields").get(0).get("field").asText()).isEqualTo("professionals[0]");
    }

    @Test
    @DisplayName("CT-20-10 / CT-00-24 profissional que não é gerente: 403 no GET e no PUT, nada muda; G-A: 200")
    void onlyManager() {
        Res get = getCommission(w.tP1, w.shopA);
        assertThat(get.status()).isEqualTo(403);
        assertThat(get.code()).isEqualTo("FORBIDDEN");
        assertThat(get.body().toString()).doesNotContain("professionalPercent");
        Res put = putCommission(w.tP1, w.shopA, settings(split(40, 60), List.of(own(w.p1, 0, 100), own(w.p2, 100, 0))));
        assertThat(put.status()).isEqualTo(403);
        // 403 vem antes da validação: mesmo um corpo inválido dá 403 para quem não é gerente.
        assertThat(putCommission(w.tP1, w.shopA, settings(split(40, 70), List.of())).status()).isEqualTo(403);
        assertThat(pctInDb(w.p1)).isNull();
        assertThat(pctInDb(w.p2)).isEqualTo(70);
        // PX é gerente na A, mas só profissional na B.
        assertThat(getCommission(w.tPX, w.shopB).status()).isEqualTo(403);
        assertThat(getCommission(w.tPX, w.shopA).status()).isEqualTo(200);
        // GP (gerente e profissional) pode.
        assertThat(getCommission(w.tGP, w.shopA).status()).isEqualTo(200);
        assertThat(getCommission(w.tGA, w.shopA).status()).isEqualTo(200);
        assertThat(putCommission(w.tGA, w.shopA, settings(split(40, 60), List.of(own(w.p1, 50, 50)))).status()).isEqualTo(200);
    }

    @Test
    @DisplayName("Outra barbearia: 404 no GET e no PUT (não revela que existe); sem token: 401")
    void otherBarbershop() {
        assertThat(getCommission(w.tGB, w.shopA).status()).isEqualTo(404);
        Res put = putCommission(w.tGB, w.shopA, settings(split(0, 100), List.of()));
        assertThat(put.status()).isEqualTo(404);
        assertThat(defaultInDb(w.shopA)).isEqualTo(60);
        assertThat(getCommission(w.tPB1, w.shopA).status()).isEqualTo(404);
        assertThat(send(req(HttpMethod.GET, "/barbershops/" + w.shopA + "/commission")).status()).isEqualTo(401);
    }

    @Test
    @DisplayName("CT-20-04 / CT-20-07 a % é gravada na conclusão e é por profissional; padrão novo vale para quem não tem própria")
    void percentFrozenAtCompletionPerProfessional() {
        UUID a = houseBook(w.corte, w.p1, "2026-10-07T10:00").id();
        UUID b = houseBook(w.corte, w.p2, "2026-10-07T10:00").id();
        UUID c = houseBook(w.corte, w.gp, "2026-10-07T10:00").id();
        // Só P1 muda para 50/50; P2 continua 70/30; o padrão vira 55/45 (vale para GP).
        Res put = putCommission(w.tGA, w.shopA, settings(split(45, 55),
                List.of(own(w.p1, 50, 50), own(w.p2, 30, 70))));
        assertThat(put.status()).isEqualTo(200);
        clock.setSp("2026-10-07T10:30:00");
        for (UUID id : List.of(a, b, c)) {
            assertThat(status(w.tGA, w.shopA, id, "COMPLETED").status()).isEqualTo(200);
        }
        Map<String, Object> ra = frozen(a);
        Map<String, Object> rb = frozen(b);
        Map<String, Object> rc = frozen(c);
        assertThat(ra).containsEntry("professional_percent", 50).containsEntry("professional_cents", 2000)
                .containsEntry("shop_cents", 2000).containsEntry("price_cents", 4000);
        assertThat(rb).containsEntry("professional_percent", 70).containsEntry("professional_cents", 2800)
                .containsEntry("shop_cents", 1200);
        assertThat(rc).containsEntry("professional_percent", 55).containsEntry("professional_cents", 2200)
                .containsEntry("shop_cents", 1800);
    }

    private Map<String, Object> frozen(UUID id) {
        return db.sql("""
                        SELECT professional_percent::int AS professional_percent, shop_percent::int AS shop_percent,
                               professional_cents, shop_cents, price_cents
                          FROM bookings WHERE id = :id
                        """)
                .param("id", id).query().singleRow();
    }
}
