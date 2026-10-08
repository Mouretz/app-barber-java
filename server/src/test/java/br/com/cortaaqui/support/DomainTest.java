package br.com.cortaaqui.support;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.http.HttpMethod;

/** Atalhos de API em cima do {@link World}. */
public abstract class DomainTest extends IntegrationTest {

    protected World w;

    @BeforeEach
    void createWorld() {
        w = World.create(db, auth, encoder);
    }

    protected static String newCode() {
        return UUID.randomUUID().toString();
    }

    protected static final String T1 = "5511987654321";
    protected static final String T2 = "5521912345678";

    protected Res clientBook(UUID shop, UUID service, UUID pro, String startLocal, String phone, String code) {
        return clientBook(shop, service, pro, startLocal, phone, code, UUID.randomUUID().toString());
    }

    protected Res clientBook(UUID shop, UUID service, UUID pro, String startLocal, String phone, String code, String key) {
        return send(req(HttpMethod.POST, "/barbershops/" + shop + "/bookings").clientCode(code).key(key)
                .body(map("serviceId", service, "professionalId", pro, "startAt", sp(startLocal),
                        "client", map("name", "Cliente Teste", "phone", phone))));
    }

    protected Res staffBook(String token, UUID shop, UUID service, UUID pro, String startLocal, String source, String name,
                            String phone) {
        return send(req(HttpMethod.POST, "/barbershops/" + shop + "/staff/bookings").token(token).newKey()
                .body(map("serviceId", service, "professionalId", pro, "startAt", sp(startLocal), "source", source,
                        "newClient", map("name", name, "phone", phone))));
    }

    /** Marcação pela Casa (gerente G-A) na Barbearia A. */
    protected Res houseBook(UUID service, UUID pro, String startLocal) {
        return staffBook(w.tGA, w.shopA, service, pro, startLocal, "STAFF", "Cliente Casa", "11912345678");
    }

    protected Res status(String token, UUID shop, UUID bookingId, String status) {
        return send(req(HttpMethod.POST, "/barbershops/" + shop + "/staff/bookings/" + bookingId + "/status").token(token)
                .newKey().body(map("status", status)));
    }

    protected Res block(String token, UUID shop, UUID pro, String startLocal, String endLocal) {
        return send(req(HttpMethod.POST, "/barbershops/" + shop + "/blocks").token(token)
                .body(map("professionalId", pro, "startAt", sp(startLocal), "endAt", sp(endLocal))));
    }

    protected Res availability(UUID shop, UUID service, UUID pro, String date) {
        return send(req(HttpMethod.GET, "/barbershops/" + shop + "/availability?serviceId=" + service + "&professionalId=" + pro
                + "&date=" + date));
    }

    /** Horários livres como "HH:mm". */
    protected List<String> slots(UUID shop, UUID service, UUID pro, String date) {
        Res r = availability(shop, service, pro, date);
        if (r.status() != 200) {
            throw new AssertionError("availability: " + r);
        }
        List<String> out = new ArrayList<>();
        for (JsonNode s : r.body().get("slots")) {
            out.add(s.get("startAt").asText().substring(11, 16));
        }
        return out;
    }

    protected String statusInDb(UUID bookingId) {
        return db.sql("SELECT status FROM bookings WHERE id = :id").param("id", bookingId).query(String.class).single();
    }

    protected int count(String sql) {
        return db.sql(sql).query(Integer.class).single();
    }

    // ------------------------------------------------------------------ escrita direta no banco (testes da constraint)

    protected UUID walkInProfile(UUID shop) {
        return db.sql("INSERT INTO client_profiles (barbershop_id, name) VALUES (:b, 'Direto') RETURNING id")
                .param("b", shop).query(UUID.class).single();
    }

    /** INSERT direto em bookings, sem passar pelo serviço. */
    protected UUID insertBookingDirect(UUID shop, UUID pro, UUID service, String startLocal, int minutes, String status) {
        LocalDateTime start = LocalDateTime.parse(startLocal);
        String canceledBy = "CANCELED".equals(status) ? "STAFF" : null;
        boolean completed = "COMPLETED".equals(status);
        return db.sql("""
                        INSERT INTO bookings (barbershop_id, professional_id, service_id, client_profile_id, source, status,
                                              start_at, end_at, service_name, duration_minutes, price_cents,
                                              professional_percent, shop_percent, professional_cents, shop_cents,
                                              canceled_by, idempotency_key, request_fingerprint)
                        VALUES (:b, :p, :s, :cp, 'STAFF', :st, CAST(:start AS timestamptz), CAST(:end AS timestamptz),
                                'X', :d, 1000, :pp, :sp, :pc, :sc, :cb, gen_random_uuid(), repeat('0', 64))
                        RETURNING id
                        """)
                .param("b", shop).param("p", pro).param("s", service).param("cp", walkInProfile(shop)).param("st", status)
                .param("start", sp(startLocal)).param("end", sp(start.plusMinutes(minutes).toString())).param("d", minutes)
                .param("pp", completed ? 60 : null).param("sp", completed ? 40 : null)
                .param("pc", completed ? 600 : null).param("sc", completed ? 400 : null).param("cb", canceledBy)
                .query(UUID.class).single();
    }

    protected UUID insertBlockDirect(UUID shop, UUID pro, String startLocal, String endLocal) {
        return db.sql("""
                        INSERT INTO blocks (barbershop_id, professional_id, start_at, end_at)
                        VALUES (:b, :p, CAST(:s AS timestamptz), CAST(:e AS timestamptz)) RETURNING id
                        """)
                .param("b", shop).param("p", pro).param("s", sp(startLocal)).param("e", sp(endLocal))
                .query(UUID.class).single();
    }
}
