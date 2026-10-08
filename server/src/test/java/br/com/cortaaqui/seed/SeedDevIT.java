package br.com.cortaaqui.seed;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.clients.ClientDirectory;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Sobe o app com o perfil dev (Flyway com db/migration + db/seed-dev) num banco novo e confere o
 * seed da Barbearia Navalha. Usa TEST_DB_URL se existir (cria um banco à parte nele); senão,
 * postgres:17 com Testcontainers.
 */
@SpringBootTest
@ActiveProfiles({"test", "dev"})
class SeedDevIT {

    private static final String SHOP = "6f1c2a10-0000-4000-8000-000000000001";
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

    @Test
    @DisplayName("Seed dev: Barbearia Navalha, Caio (gerente) e Helena, serviços 4000/3000/6000, João sem aparelho e Rafael com aparelho")
    void seedLoaded() {
        assertThat(db.sql("SELECT name FROM barbershops WHERE id = CAST(:id AS uuid)").param("id", SHOP)
                .query(String.class).single()).isEqualTo("Barbearia Navalha");

        List<Map<String, Object>> staff = db.sql("""
                        SELECT u.id, u.name, u.email, u.password_hash, m.is_manager, m.professional_id
                          FROM staff_users u JOIN memberships m ON m.user_id = u.id
                         WHERE m.barbershop_id = CAST(:b AS uuid) ORDER BY u.name
                        """).param("b", SHOP).query().listOfRows();
        assertThat(staff).extracting(m -> m.get("name")).containsExactly("Caio", "Helena");
        assertThat(staff).extracting(m -> m.get("email")).containsExactly("caio@navalha.dev", "helena@navalha.dev");
        assertThat(staff).extracting(m -> m.get("id").toString())
                .containsExactly("6f1c2a10-0000-4000-8000-0000000000f1", "6f1c2a10-0000-4000-8000-0000000000f2");
        assertThat(staff).extracting(m -> m.get("is_manager")).containsExactly(true, false);
        assertThat(staff).extracting(m -> m.get("professional_id").toString())
                .containsExactly("6f1c2a10-0000-4000-8000-0000000000b1", "6f1c2a10-0000-4000-8000-0000000000b2");
        assertThat(staff).allSatisfy(m ->
                assertThat(encoder.matches("navalha-dev-123", (String) m.get("password_hash"))).isTrue());

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
    }
}
