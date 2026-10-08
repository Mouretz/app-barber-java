package br.com.cortaaqui.support;

import br.com.cortaaqui.auth.AuthService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Base dos testes com Postgres de verdade (nada de H2: a constraint EXCLUDE só existe no Postgres).
 * Usa TEST_DB_URL / TEST_DB_USER / TEST_DB_PASSWORD se existirem; senão sobe postgres:17 com Testcontainers.
 * Cada teste começa com o banco vazio e o relógio em 07/10/2026 09:00 (Brasília).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestClockConfig.class)
public abstract class IntegrationTest {

    private static PostgreSQLContainer<?> container;

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry r) {
        String url = System.getenv("TEST_DB_URL");
        if (url != null && !url.isBlank()) {
            r.add("spring.datasource.url", () -> url);
            r.add("spring.datasource.username", () -> envOr("TEST_DB_USER", "postgres"));
            r.add("spring.datasource.password", () -> envOr("TEST_DB_PASSWORD", ""));
            return;
        }
        synchronized (IntegrationTest.class) {
            if (container == null) {
                container = new PostgreSQLContainer<>("postgres:17");
                container.start();
            }
        }
        r.add("spring.datasource.url", container::getJdbcUrl);
        r.add("spring.datasource.username", container::getUsername);
        r.add("spring.datasource.password", container::getPassword);
    }

    private static String envOr(String name, String fallback) {
        String v = System.getenv(name);
        return v == null ? fallback : v;
    }

    @Autowired
    protected MockMvc mvc;
    @Autowired
    protected JdbcClient db;
    @Autowired
    protected MutableClock clock;
    @Autowired
    protected ObjectMapper json;
    @Autowired
    protected AuthService auth;
    @Autowired
    protected PasswordEncoder encoder;

    @BeforeEach
    void resetDatabaseAndClock() {
        db.sql("TRUNCATE barbershops, staff_users, clients RESTART IDENTITY CASCADE").update();
        clock.setSp("2026-10-07T09:00:00");
    }

    // ------------------------------------------------------------------ HTTP

    public record Res(int status, JsonNode body) {
        public String code() {
            return body == null || body.get("code") == null ? null : body.get("code").asText();
        }

        public UUID id() {
            return UUID.fromString(body.get("id").asText());
        }

        @Override
        public String toString() {
            return status + " " + body;
        }
    }

    public static final class Req {
        final HttpMethod method;
        final String path;
        String token;
        String clientCode;
        String idempotencyKey;
        Object body;

        Req(HttpMethod method, String path) {
            this.method = method;
            this.path = path;
        }

        public Req token(String t) {
            this.token = t;
            return this;
        }

        public Req clientCode(String c) {
            this.clientCode = c;
            return this;
        }

        public Req key(String k) {
            this.idempotencyKey = k;
            return this;
        }

        public Req key(UUID k) {
            this.idempotencyKey = k.toString();
            return this;
        }

        public Req newKey() {
            this.idempotencyKey = UUID.randomUUID().toString();
            return this;
        }

        public Req body(Object b) {
            this.body = b;
            return this;
        }
    }

    protected static Req req(HttpMethod m, String path) {
        return new Req(m, path);
    }

    protected Res send(Req r) {
        try {
            MockHttpServletRequestBuilder b = MockMvcRequestBuilders.request(r.method, "/api/v1" + r.path);
            if (r.token != null) {
                b.header("Authorization", "Bearer " + r.token);
            }
            if (r.clientCode != null) {
                b.header("X-Client-Code", r.clientCode);
            }
            if (r.idempotencyKey != null) {
                b.header("Idempotency-Key", r.idempotencyKey);
            }
            if (r.body != null) {
                b.contentType(MediaType.APPLICATION_JSON)
                        .content(r.body instanceof String s ? s : json.writeValueAsString(r.body));
            }
            MockHttpServletResponse res = mvc.perform(b).andReturn().getResponse();
            String content = res.getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
            return new Res(res.getStatus(), content.isBlank() ? null : json.readTree(content));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    protected Res get(String path, String token) {
        return send(req(HttpMethod.GET, path).token(token));
    }

    /** Mapa com ordem e aceitando null (Map.of não aceita). */
    protected static Map<String, Object> map(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            m.put((String) kv[i], kv[i + 1]);
        }
        return m;
    }

    /** "2026-10-07T10:00" (Brasília) -> "2026-10-07T10:00:00-03:00". */
    protected static String sp(String localIso) {
        return java.time.LocalDateTime.parse(localIso).atZone(br.com.cortaaqui.common.SpTime.ZONE).toOffsetDateTime().toString();
    }

    // ------------------------------------------------------------------ concorrência

    /** Solta todas as tarefas juntas (CountDownLatch) em threads separadas e devolve os resultados. */
    protected <T> List<T> together(List<Callable<T>> tasks) {
        ExecutorService pool = Executors.newFixedThreadPool(tasks.size());
        try {
            CountDownLatch ready = new CountDownLatch(tasks.size());
            CountDownLatch go = new CountDownLatch(1);
            List<Future<T>> futures = new ArrayList<>();
            for (Callable<T> t : tasks) {
                futures.add(pool.submit(() -> {
                    ready.countDown();
                    go.await();
                    return t.call();
                }));
            }
            ready.await();
            go.countDown();
            List<T> out = new ArrayList<>();
            for (Future<T> f : futures) {
                out.add(f.get());
            }
            return out;
        } catch (Exception e) {
            throw new RuntimeException(e);
        } finally {
            pool.shutdownNow();
        }
    }
}
