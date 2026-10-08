package br.com.cortaaqui.support;

import br.com.cortaaqui.auth.AuthService;
import java.time.LocalDate;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;

/**
 * Dados de teste da seção 5 do plano da QA.
 * A: P1 (60/40, padrão), P2 (70/30), G-A (só gerente), GP (gerente e profissional).
 * B: PB1 (profissional), G-B (gerente). PX: gerente na A e profissional na B.
 * Serviços da A: Corte 30 min R$ 40, Barba 30 min R$ 30, Combo 60 min R$ 65. Expediente 08:00–19:00 todo dia.
 */
public final class World {

    public static final String PASSWORD = "senha-de-teste-123";
    private static String passwordHash;

    public UUID shopA, shopB;
    public UUID p1, p2, gp, pb1, px;
    public UUID corte, barba, combo, corteB;
    public String tP1, tP2, tGA, tGP, tPB1, tGB, tPX;
    public UUID uGA;

    private final JdbcClient db;

    private World(JdbcClient db) {
        this.db = db;
    }

    public static synchronized String hash(org.springframework.security.crypto.password.PasswordEncoder encoder) {
        if (passwordHash == null) {
            passwordHash = encoder.encode(PASSWORD);
        }
        return passwordHash;
    }

    public static World create(JdbcClient db, AuthService auth, org.springframework.security.crypto.password.PasswordEncoder encoder) {
        World w = new World(db);
        String hash = hash(encoder);
        w.shopA = w.shop("Barbearia A", "Pinheiros");
        w.shopB = w.shop("Barbearia B", "Centro");
        w.p1 = w.professional(w.shopA, "P1", null);
        w.p2 = w.professional(w.shopA, "P2", 70);
        w.gp = w.professional(w.shopA, "GP", null);
        w.pb1 = w.professional(w.shopB, "PB1", null);
        w.px = w.professional(w.shopB, "PX", null);
        w.corte = w.service(w.shopA, "Corte", 30, 4000);
        w.barba = w.service(w.shopA, "Barba", 30, 3000);
        w.combo = w.service(w.shopA, "Combo", 60, 6500);
        w.corteB = w.service(w.shopB, "Corte B", 30, 5000);
        for (UUID p : new UUID[] {w.p1, w.p2, w.gp}) {
            w.hours(w.shopA, p, 8 * 60, 19 * 60);
        }
        for (UUID p : new UUID[] {w.pb1, w.px}) {
            w.hours(w.shopB, p, 8 * 60, 19 * 60);
        }
        UUID uP1 = w.user("P1", "p1@a.test", hash);
        UUID uP2 = w.user("P2", "p2@a.test", hash);
        w.uGA = w.user("G-A", "ga@a.test", hash);
        UUID uGP = w.user("GP", "gp@a.test", hash);
        UUID uPB1 = w.user("PB1", "pb1@b.test", hash);
        UUID uGB = w.user("G-B", "gb@b.test", hash);
        UUID uPX = w.user("PX", "px@test", hash);
        w.member(w.shopA, uP1, false, w.p1);
        w.member(w.shopA, uP2, false, w.p2);
        w.member(w.shopA, w.uGA, true, null);
        w.member(w.shopA, uGP, true, w.gp);
        w.member(w.shopB, uPB1, false, w.pb1);
        w.member(w.shopB, uGB, true, null);
        w.member(w.shopA, uPX, true, null);
        w.member(w.shopB, uPX, false, w.px);
        w.tP1 = auth.createSession(uP1);
        w.tP2 = auth.createSession(uP2);
        w.tGA = auth.createSession(w.uGA);
        w.tGP = auth.createSession(uGP);
        w.tPB1 = auth.createSession(uPB1);
        w.tGB = auth.createSession(uGB);
        w.tPX = auth.createSession(uPX);
        return w;
    }

    public UUID shop(String name, String neighborhood) {
        return db.sql("INSERT INTO barbershops (name, neighborhood, city, address) VALUES (:n, :nb, 'São Paulo', 'Rua X, 1') RETURNING id")
                .param("n", name).param("nb", neighborhood).query(UUID.class).single();
    }

    public UUID professional(UUID shop, String name, Integer pct) {
        return db.sql("INSERT INTO professionals (barbershop_id, name, professional_percent) VALUES (:b, :n, :p) RETURNING id")
                .param("b", shop).param("n", name).param("p", pct).query(UUID.class).single();
    }

    public UUID service(UUID shop, String name, int minutes, int cents) {
        return db.sql("INSERT INTO services (barbershop_id, name, duration_minutes, price_cents) VALUES (:b, :n, :d, :c) RETURNING id")
                .param("b", shop).param("n", name).param("d", minutes).param("c", cents).query(UUID.class).single();
    }

    /** Expediente todos os dias, valendo desde 01/01/2026. */
    public void hours(UUID shop, UUID professional, int startMinute, int endMinute) {
        UUID v = db.sql("INSERT INTO working_hours_versions (barbershop_id, professional_id, valid_from) VALUES (:b, :p, :d) RETURNING id")
                .param("b", shop).param("p", professional).param("d", LocalDate.of(2026, 1, 1)).query(UUID.class).single();
        for (int wd = 1; wd <= 7; wd++) {
            db.sql("INSERT INTO working_hours_windows (barbershop_id, version_id, weekday, start_minute, end_minute) VALUES (:b, :v, :wd, :s, :e)")
                    .param("b", shop).param("v", v).param("wd", wd).param("s", startMinute).param("e", endMinute).update();
        }
    }

    public UUID user(String name, String email, String hash) {
        return db.sql("INSERT INTO staff_users (name, email, password_hash) VALUES (:n, :e, :h) RETURNING id")
                .param("n", name).param("e", email).param("h", hash).query(UUID.class).single();
    }

    public void member(UUID shop, UUID user, boolean manager, UUID professional) {
        db.sql("INSERT INTO memberships (barbershop_id, user_id, is_manager, professional_id) VALUES (:b, :u, :m, :p)")
                .param("b", shop).param("u", user).param("m", manager).param("p", professional).update();
    }
}
