package br.com.cortaaqui.seed;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.clients.ClientDirectory;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Sobe o app com o perfil dev (Flyway com db/migration + db/seed-dev) num banco novo e confere o
 * seed da Barbearia Navalha. Usa TEST_DB_URL se existir (cria um banco à parte nele); senão,
 * postgres:17 com Testcontainers.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles({"test", "dev"})
class SeedDevIT {

    private static final String SHOP = "6f1c2a10-0000-4000-8000-000000000001";
    private static final String MARINA = "6f1c2a10-0000-4000-8000-0000000000f3";
    private static final String HELENA_PRO = "6f1c2a10-0000-4000-8000-0000000000b2";
    private static final String BOOKING_D2 = "6f1c2a10-0000-4000-8000-0000000000d2";
    /** Senha de dev do seed (só local; no banco fica só o hash BCrypt). */
    private static final String DEV_PASSWORD = "navalha-dev-123";
    private static PostgreSQLContainer<?> container;

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry r) throws Exception {
        String url = System.getenv("TEST_DB_URL");
        String user;
        String password;
        if (url != null && !url.isBlank()) {
            user = envOr("TEST_DB_USER", "postgres");
            password = envOr("TEST_DB_PASSWORD", "");
        } else {
            synchronized (SeedDevIT.class) {
                if (container == null) {
                    container = new PostgreSQLContainer<>("postgres:17");
                    container.start();
                }
            }
            url = container.getJdbcUrl();
            user = container.getUsername();
            password = container.getPassword();
        }
        String db = "cortaaqui_seed_dev_check";
        try (Connection c = DriverManager.getConnection(url, user, password); Statement st = c.createStatement()) {
            st.execute("DROP DATABASE IF EXISTS " + db + " WITH (FORCE)");
            st.execute("CREATE DATABASE " + db);
        }
        String seedUrl = url.replaceFirst("/[^/?]+(\\?|$)", "/" + db + "$1");
        r.add("spring.datasource.url", () -> seedUrl);
        r.add("spring.datasource.username", () -> user);
        r.add("spring.datasource.password", () -> password);
    }

    private static String envOr(String name, String fallback) {
        String v = System.getenv(name);
        return v == null ? fallback : v;
    }

    @Autowired
    JdbcClient db;
    @Autowired
    PasswordEncoder encoder;
    @Autowired
    ClientDirectory directory;
    @Autowired
    MockMvc mvc;
    @Autowired
    ObjectMapper json;

    @Test
    @DisplayName("Seed dev: Barbearia Navalha, Caio (gerente), Helena e Marina (gerente que não corta), serviços 4000/3000/6000, João sem aparelho e Rafael com aparelho")
    void seedLoaded() {
        assertThat(db.sql("SELECT name FROM barbershops WHERE id = CAST(:id AS uuid)").param("id", SHOP)
                .query(String.class).single()).isEqualTo("Barbearia Navalha");

        List<Map<String, Object>> staff = db.sql("""
                        SELECT u.id, u.name, u.email, u.password_hash, m.is_manager, m.professional_id
                          FROM staff_users u JOIN memberships m ON m.user_id = u.id
                         WHERE m.barbershop_id = CAST(:b AS uuid) ORDER BY u.name
                        """).param("b", SHOP).query().listOfRows();
        assertThat(staff).extracting(m -> m.get("name")).containsExactly("Caio", "Helena", "Marina");
        assertThat(staff).extracting(m -> m.get("email"))
                .containsExactly("caio@navalha.dev", "helena@navalha.dev", "marina@navalha.dev");
        assertThat(staff).extracting(m -> m.get("id").toString())
                .containsExactly("6f1c2a10-0000-4000-8000-0000000000f1", "6f1c2a10-0000-4000-8000-0000000000f2", MARINA);
        assertThat(staff).extracting(m -> m.get("is_manager")).containsExactly(true, false, true);
        assertThat(staff).extracting(m -> m.get("professional_id") == null ? null : m.get("professional_id").toString())
                .containsExactly("6f1c2a10-0000-4000-8000-0000000000b1", HELENA_PRO, null);
        assertThat(staff).allSatisfy(m ->
                assertThat(encoder.matches(DEV_PASSWORD, (String) m.get("password_hash"))).isTrue());
        // Marina não corta: nenhuma linha em professionals com o nome dela.
        assertThat(db.sql("SELECT count(*) FROM professionals WHERE name = 'Marina'").query(Integer.class).single()).isZero();

        List<Map<String, Object>> services = db.sql("""
                        SELECT id, name, duration_minutes, price_cents FROM services
                         WHERE barbershop_id = CAST(:b AS uuid) ORDER BY id
                        """).param("b", SHOP).query().listOfRows();
        assertThat(services).extracting(m -> m.get("id").toString()).containsExactly(
                "6f1c2a10-0000-4000-8000-0000000000a1", "6f1c2a10-0000-4000-8000-0000000000a2",
                "6f1c2a10-0000-4000-8000-0000000000a3");
        assertThat(services).extracting(m -> m.get("name")).containsExactly("Corte", "Barba", "Corte + Barba");
        assertThat(services).extracting(m -> m.get("price_cents")).containsExactly(4000, 3000, 6000);
        assertThat(services).extracting(m -> m.get("duration_minutes")).containsExactly(30, 30, 60);

        Map<String, Object> joao = db.sql("SELECT phone, device_code_hash FROM clients WHERE id = CAST(:id AS uuid)")
                .param("id", "6f1c2a10-0000-4000-8000-0000000000c1").query().singleRow();
        assertThat(joao.get("phone")).isEqualTo("5511987654321");
        assertThat(joao.get("device_code_hash")).isNull();
        Map<String, Object> rafael = db.sql("SELECT phone, device_code_hash FROM clients WHERE id = CAST(:id AS uuid)")
                .param("id", "6f1c2a10-0000-4000-8000-0000000000c2").query().singleRow();
        assertThat(rafael.get("phone")).isEqualTo("5521912345678");
        assertThat((String) rafael.get("device_code_hash")).hasSize(64);
        // o hash é o do código fictício documentado no seed: o servidor acha o Rafael por ele
        assertThat(directory.findByCode("6f1c2a10-0000-4000-8000-0000000000dd"))
                .contains(UUID.fromString("6f1c2a10-0000-4000-8000-0000000000c2"));

        assertThat(db.sql("SELECT count(*) FROM flyway_schema_history WHERE script LIKE '%seed_barbearia_navalha%' AND success")
                .query(Integer.class).single()).isEqualTo(1);
        assertThat(db.sql("SELECT count(*) FROM flyway_schema_history WHERE script LIKE '%seed_marina_gerente%' AND success")
                .query(Integer.class).single()).isEqualTo(1);
    }

    @Test
    @DisplayName("Seed dev: Marina faz login, /auth/me só MANAGER sem professionalId, fora da equipe e da agenda, com caixa de gerente")
    void marinaManagerWhoDoesNotCut() throws Exception {
        JsonNode session = call(MockMvcRequestBuilders.post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("email", "marina@navalha.dev", "password", DEV_PASSWORD))), null, 200);
        String token = session.get("accessToken").asText();

        JsonNode me = call(MockMvcRequestBuilders.get("/api/v1/auth/me"), token, 200);
        assertThat(me.get("id").asText()).isEqualTo(MARINA);
        assertThat(me.get("name").asText()).isEqualTo("Marina");
        assertThat(me.get("memberships")).hasSize(1);
        JsonNode m = me.get("memberships").get(0);
        assertThat(m.get("barbershopId").asText()).isEqualTo(SHOP);
        assertThat(m.get("roles")).extracting(JsonNode::asText).containsExactly("MANAGER");
        assertThat(m.get("professionalId") == null || m.get("professionalId").isNull()).isTrue();

        JsonNode team = call(MockMvcRequestBuilders.get("/api/v1/barbershops/" + SHOP + "/professionals"), token, 200);
        assertThat(team).extracting(p -> p.get("name").asText()).containsExactlyInAnyOrder("Caio", "Helena");
        assertThat(team).allSatisfy(p -> assertThat(p.get("active").asBoolean()).isTrue());

        String today = db.sql("SELECT CAST((now() AT TIME ZONE 'America/Sao_Paulo') AS date)::text").query(String.class).single();
        JsonNode agenda = call(MockMvcRequestBuilders.get("/api/v1/barbershops/" + SHOP + "/agenda").param("date", today),
                token, 200);
        assertThat(agenda.get("professionals")).extracting(p -> p.get("professional").get("name").asText())
                .doesNotContain("Marina").contains("Caio", "Helena");

        // Acesso de gerente: caixa do mês do atendimento concluído, com a parte da casa.
        JsonNode cash = call(MockMvcRequestBuilders.get("/api/v1/barbershops/" + SHOP + "/cash")
                .param("month", bookingMonth()), token, 200);
        assertThat(cash.get("totals").get("completedCount").asLong()).isEqualTo(1);
        assertThat(cash.get("totals").get("grossCents").asLong()).isEqualTo(6000);
        assertThat(cash.get("totals").get("shopCents").asLong()).isEqualTo(2400);
        assertThat(cash.get("totals").get("professionalCents").asLong()).isEqualTo(3600);
    }

    @Test
    @DisplayName("Seed dev: atendimento concluído do mock (d2): Helena, Corte + Barba, João pelo app, hoje-7 às 15:00 SP, 3600/2400")
    void completedBookingFromMock() {
        Map<String, Object> b = db.sql("""
                        SELECT professional_id, service_id, client_profile_id, client_id, source, status, service_name,
                               duration_minutes, price_cents, professional_percent, shop_percent, professional_cents,
                               shop_cents, completed_at IS NOT NULL AS completed,
                               (start_at AT TIME ZONE 'America/Sao_Paulo')::text AS start_sp,
                               (end_at AT TIME ZONE 'America/Sao_Paulo')::text AS end_sp,
                               (((now() AT TIME ZONE 'America/Sao_Paulo')::date - 7) + time '15:00')::text AS expected_start
                          FROM bookings WHERE id = CAST(:id AS uuid)
                        """).param("id", BOOKING_D2).query().singleRow();
        assertThat(b.get("professional_id").toString()).isEqualTo(HELENA_PRO);
        assertThat(b.get("service_id").toString()).isEqualTo("6f1c2a10-0000-4000-8000-0000000000a3");
        assertThat(b.get("client_profile_id").toString()).isEqualTo("6f1c2a10-0000-4000-8000-0000000000c1");
        assertThat(b.get("client_id").toString()).isEqualTo("6f1c2a10-0000-4000-8000-0000000000c1");
        assertThat(b.get("source")).isEqualTo("CLIENT_APP");
        assertThat(b.get("status")).isEqualTo("COMPLETED");
        assertThat(b.get("service_name")).isEqualTo("Corte + Barba");
        assertThat(b.get("duration_minutes")).isEqualTo(60);
        assertThat(b.get("price_cents")).isEqualTo(6000);
        assertThat(((Number) b.get("professional_percent")).intValue()).isEqualTo(60);
        assertThat(((Number) b.get("shop_percent")).intValue()).isEqualTo(40);
        assertThat(b.get("professional_cents")).isEqualTo(3600);
        assertThat(b.get("shop_cents")).isEqualTo(2400);
        assertThat(b.get("completed")).isEqualTo(true);
        assertThat(b.get("start_sp")).isEqualTo(b.get("expected_start"));
        assertThat((String) b.get("end_sp")).endsWith("16:00:00");
        // o trigger ocupou a agenda da Helena (concluído continua ocupando)
        assertThat(db.sql("SELECT count(*) FROM agenda_occupancy WHERE booking_id = CAST(:id AS uuid)")
                .param("id", BOOKING_D2).query(Integer.class).single()).isEqualTo(1);
    }

    private String bookingMonth() {
        return db.sql("SELECT to_char(start_at AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM') FROM bookings WHERE id = CAST(:id AS uuid)")
                .param("id", BOOKING_D2).query(String.class).single();
    }

    private JsonNode call(MockHttpServletRequestBuilder req, String token, int expectedStatus) throws Exception {
        if (token != null) {
            req.header("Authorization", "Bearer " + token);
        }
        MvcResult r = mvc.perform(req).andReturn();
        String body = r.getResponse().getContentAsString();
        assertThat(r.getResponse().getStatus()).as(body).isEqualTo(expectedStatus);
        return json.readTree(body);
    }
}
