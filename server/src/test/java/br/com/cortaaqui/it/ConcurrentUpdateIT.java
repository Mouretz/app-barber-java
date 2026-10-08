package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import java.sql.Connection;
import java.sql.Statement;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpMethod;

/**
 * 409 CONCURRENT_UPDATE (pedido do tech lead, QA e PO, 08/10). Quando o banco recusa por causa de
 * outra operação ao mesmo tempo (deadlock 40P01, serialização 40001) e a repetição do
 * TransientDbRetry também falha, a resposta é 409 CONCURRENT_UPDATE, com corpo, em criar
 * agendamento (app e Casa), criar bloqueio, mudar status e cancelar. Conflito de horário de
 * verdade continua 409 SLOT_TAKEN.
 *
 * <p>Como forçar: um trigger só de teste (BEFORE, na tabela da operação) levanta o SQLSTATE
 * pedido nas N primeiras vezes. O contador é uma sequence, que não volta no ROLLBACK, então
 * dá para dizer "falha na 1ª e na 2ª tentativa" ou "só na 1ª". O erro sai do Postgres de
 * verdade e passa pelo driver, pela tradução do Spring e pelo handler, como em produção.
 */
class ConcurrentUpdateIT extends DomainTest {

    private static final String MESSAGE = "Não deu pra concluir agora. Tente de novo.";
    /** Advisory lock que o teste segura para a 1ª tentativa esperar dentro do trigger. */
    private static final long GATE = 4242;

    @Autowired
    private DataSource dataSource;

    /** Liga a falha forçada: as {@code times} primeiras linhas em {@code table} ({@code event}) levam {@code sqlState}. */
    private void failNext(String table, String event, String sqlState, int times) {
        failNext(table, event, sqlState, times, false);
    }

    /**
     * Igual, mas com {@code waitGate}: antes de falhar, a tentativa espera o advisory lock
     * {@link #GATE} (que o teste segura). Assim dá para fazer outra coisa no banco no meio da
     * 1ª tentativa, com ela já tendo lido o estado, e só então deixar ela falhar.
     */
    private void failNext(String table, String event, String sqlState, int times, boolean waitGate) {
        dropForcedFailure();
        db.sql("CREATE SEQUENCE test_forced_fail_seq").update();
        db.sql("""
                CREATE OR REPLACE FUNCTION test_forced_fail() RETURNS trigger LANGUAGE plpgsql AS $$
                BEGIN
                    IF nextval('test_forced_fail_seq') <= TG_ARGV[1]::int THEN
                        IF TG_ARGV[2]::boolean THEN
                            PERFORM pg_advisory_xact_lock_shared(4242); -- GATE
                        END IF;
                        RAISE EXCEPTION 'falha forçada pelo teste (%)', TG_ARGV[0] USING ERRCODE = TG_ARGV[0];
                    END IF;
                    IF TG_OP = 'DELETE' THEN
                        RETURN OLD;
                    END IF;
                    RETURN NEW;
                END $$
                """).update();
        db.sql("CREATE TRIGGER test_forced_fail BEFORE " + event + " ON " + table
                + " FOR EACH ROW EXECUTE FUNCTION test_forced_fail('" + sqlState + "', '" + times + "', '" + waitGate + "')")
                .update();
    }

    /** Quantas vezes o trigger rodou (= tentativas que chegaram na escrita). */
    private long attempts() {
        return db.sql("SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM test_forced_fail_seq").query(Long.class).single();
    }

    @AfterEach
    void dropForcedFailure() {
        db.sql("DROP TRIGGER IF EXISTS test_forced_fail ON bookings").update();
        db.sql("DROP TRIGGER IF EXISTS test_forced_fail ON blocks").update();
        db.sql("DROP TRIGGER IF EXISTS test_forced_fail ON booking_status_requests").update();
        db.sql("DROP FUNCTION IF EXISTS test_forced_fail() CASCADE").update();
        db.sql("DROP SEQUENCE IF EXISTS test_forced_fail_seq").update();
    }

    private void stopFailing() {
        dropForcedFailure();
    }

    private static void assertConcurrentUpdate(Res r) {
        assertThat(r.status()).as(r.toString()).isEqualTo(409);
        assertThat(r.code()).as(r.toString()).isEqualTo("CONCURRENT_UPDATE");
        assertThat(r.body().get("status").asInt()).isEqualTo(409);
        assertThat(r.body().get("title").asText()).isEqualTo(MESSAGE);
        assertThat(r.body().get("detail")).isNotNull();
        assertThat(r.body().get("fields")).isNull();
    }

    private Res clientCreate(String key, String code) {
        return clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code, key);
    }

    private Res staffCreate(String key) {
        return send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/staff/bookings").token(w.tGA).key(key)
                .body(map("serviceId", w.corte, "professionalId", w.p1, "startAt", sp("2026-10-08T10:00"), "source", "COUNTER",
                        "newClient", map("name", "Balcão"))));
    }

    private Res statusWithKey(UUID bookingId, String status, String key) {
        return send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/staff/bookings/" + bookingId + "/status").token(w.tGA)
                .key(key).body(map("status", status)));
    }

    private Res clientCancel(String code, UUID bookingId, String key) {
        return send(req(HttpMethod.POST, "/me/bookings/" + bookingId + "/cancel").clientCode(code).key(key));
    }

    // ------------------------------------------------------------------ criar agendamento

    @Test
    @DisplayName("App: deadlock na 1ª e na 2ª tentativa dá 409 CONCURRENT_UPDATE com corpo (não SLOT_TAKEN), nada gravado; a mesma chave depois dá 201")
    void clientCreateGivesUp() {
        String code = newCode();
        String key = UUID.randomUUID().toString();
        failNext("bookings", "INSERT", "40P01", 2);
        Res r = clientCreate(key, code);
        assertConcurrentUpdate(r);
        assertThat(attempts()).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM bookings")).isZero();
        // O código do aparelho não ficou preso (a transação inteira voltou).
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL")).isZero();
        // O horário estava livre o tempo todo.
        assertThat(slots(w.shopA, w.corte, w.p1, "2026-10-08")).contains("10:00");

        stopFailing();
        Res again = clientCreate(key, code);
        assertThat(again.status()).as(again.toString()).isEqualTo(201);
        assertThat(count("SELECT count(*) FROM bookings")).isEqualTo(1);
    }

    @Test
    @DisplayName("App: falha de serialização (40001) nas duas tentativas também dá 409 CONCURRENT_UPDATE")
    void clientCreateSerializationGivesUp() {
        failNext("bookings", "INSERT", "40001", 2);
        assertConcurrentUpdate(clientCreate(UUID.randomUUID().toString(), newCode()));
        assertThat(attempts()).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM bookings")).isZero();
    }

    @Test
    @DisplayName("App: deadlock só na 1ª tentativa: a repetição entra (201), um agendamento só")
    void clientCreateRetrySucceeds() {
        failNext("bookings", "INSERT", "40P01", 1);
        Res r = clientCreate(UUID.randomUUID().toString(), newCode());
        assertThat(r.status()).as(r.toString()).isEqualTo(201);
        assertThat(attempts()).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM bookings")).isEqualTo(1);
    }

    @Test
    @DisplayName("Casa (balcão): deadlock nas duas tentativas dá 409 CONCURRENT_UPDATE, sem ficha nem agendamento; a mesma chave depois dá 201")
    void staffCreateGivesUp() {
        String key = UUID.randomUUID().toString();
        failNext("bookings", "INSERT", "40P01", 2);
        assertConcurrentUpdate(staffCreate(key));
        assertThat(attempts()).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM bookings")).isZero();
        assertThat(count("SELECT count(*) FROM client_profiles WHERE name = 'Balcão'")).isZero();

        stopFailing();
        Res again = staffCreate(key);
        assertThat(again.status()).as(again.toString()).isEqualTo(201);
    }

    // ------------------------------------------------------------------ conflito de verdade continua SLOT_TAKEN

    @Test
    @DisplayName("Conflito de verdade segue 409 SLOT_TAKEN: horário já marcado (app e Casa), em cima de bloqueio e bloqueio sobre bloqueio")
    void realConflictStaysSlotTaken() {
        assertThat(houseBook(w.corte, w.p1, "2026-10-08T10:00").status()).isEqualTo(201);
        Res app = clientCreate(UUID.randomUUID().toString(), newCode());
        assertThat(app.status()).as(app.toString()).isEqualTo(409);
        assertThat(app.code()).isEqualTo("SLOT_TAKEN");
        Res casa = houseBook(w.combo, w.p1, "2026-10-08T09:30");
        assertThat(casa.status()).isEqualTo(409);
        assertThat(casa.code()).isEqualTo("SLOT_TAKEN");

        assertThat(block(w.tGA, w.shopA, w.p1, "2026-10-08T14:00", "2026-10-08T15:00").status()).isEqualTo(201);
        Res onBlock = houseBook(w.corte, w.p1, "2026-10-08T14:30");
        assertThat(onBlock.status()).isEqualTo(409);
        assertThat(onBlock.code()).isEqualTo("SLOT_TAKEN");
        Res blockOnBlock = block(w.tGA, w.shopA, w.p1, "2026-10-08T14:30", "2026-10-08T15:30");
        assertThat(blockOnBlock.status()).isEqualTo(409);
        assertThat(blockOnBlock.code()).isEqualTo("SLOT_TAKEN");
    }

    @Test
    @DisplayName("Deadlock na 1ª tentativa e conflito de verdade na 2ª: 409 SLOT_TAKEN (o horário está mesmo ocupado)")
    void retryThenRealConflictIsSlotTaken() {
        assertThat(houseBook(w.corte, w.p1, "2026-10-08T10:00").status()).isEqualTo(201);
        failNext("bookings", "INSERT", "40P01", 1);
        Res r = clientCreate(UUID.randomUUID().toString(), newCode());
        assertThat(r.status()).as(r.toString()).isEqualTo(409);
        assertThat(r.code()).isEqualTo("SLOT_TAKEN");
        assertThat(attempts()).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM bookings")).isEqualTo(1);
    }

    // ------------------------------------------------------------------ bloqueio

    @Test
    @DisplayName("Bloqueio: deadlock nas duas tentativas dá 409 CONCURRENT_UPDATE e nada é criado; só na 1ª, entra (201)")
    void blockCreate() {
        failNext("blocks", "INSERT", "40P01", 2);
        assertConcurrentUpdate(block(w.tGA, w.shopA, w.p1, "2026-10-08T14:00", "2026-10-08T15:00"));
        assertThat(attempts()).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM blocks")).isZero();

        failNext("blocks", "INSERT", "40P01", 1);
        Res ok = block(w.tGA, w.shopA, w.p1, "2026-10-08T14:00", "2026-10-08T15:00");
        assertThat(ok.status()).as(ok.toString()).isEqualTo(201);
        assertThat(count("SELECT count(*) FROM blocks")).isEqualTo(1);
    }

    // ------------------------------------------------------------------ status e cancelamento

    @Test
    @DisplayName("Mudar status: deadlock nas duas tentativas dá 409 CONCURRENT_UPDATE (não VALIDATION_ERROR); status e chave não ficam gravados; a mesma chave depois conclui")
    void statusGivesUp() {
        UUID id = houseBook(w.corte, w.p1, "2026-10-08T10:00").id();
        clock.setSp("2026-10-08T10:10:00");
        String key = UUID.randomUUID().toString();
        failNext("bookings", "UPDATE", "40P01", 2);
        assertConcurrentUpdate(statusWithKey(id, "COMPLETED", key));
        assertThat(attempts()).isEqualTo(2);
        assertThat(statusInDb(id)).isEqualTo("SCHEDULED");
        assertThat(count("SELECT count(*) FROM booking_status_requests")).isZero();

        stopFailing();
        Res again = statusWithKey(id, "COMPLETED", key);
        assertThat(again.status()).as(again.toString()).isEqualTo(200);
        assertThat(statusInDb(id)).isEqualTo("COMPLETED");
    }

    @Test
    @DisplayName("Mudar status: deadlock só na 1ª tentativa: a repetição cancela (200)")
    void statusRetrySucceeds() {
        UUID id = houseBook(w.corte, w.p1, "2026-10-08T10:00").id();
        failNext("bookings", "UPDATE", "40P01", 1);
        Res r = statusWithKey(id, "CANCELED", UUID.randomUUID().toString());
        assertThat(r.status()).as(r.toString()).isEqualTo(200);
        assertThat(attempts()).isEqualTo(2);
        assertThat(statusInDb(id)).isEqualTo("CANCELED");
    }

    @Test
    @DisplayName("Cliente cancela: deadlock nas duas tentativas dá 409 CONCURRENT_UPDATE; continua agendado; a mesma chave depois cancela")
    void clientCancelGivesUp() {
        String code = newCode();
        UUID id = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", T1, code).id();
        String key = UUID.randomUUID().toString();
        failNext("bookings", "UPDATE", "40P01", 2);
        assertConcurrentUpdate(clientCancel(code, id, key));
        assertThat(attempts()).isEqualTo(2);
        assertThat(statusInDb(id)).isEqualTo("SCHEDULED");

        stopFailing();
        Res again = clientCancel(code, id, key);
        assertThat(again.status()).as(again.toString()).isEqualTo(200);
        assertThat(statusInDb(id)).isEqualTo("CANCELED");
    }

    @Test
    @DisplayName("lock_timeout (55P03) ao mudar status: 409 CONCURRENT_UPDATE com corpo, SEM 2ª tentativa (o trigger roda 1 vez)")
    void lockNotAvailableIsConcurrentUpdate() {
        UUID id = houseBook(w.corte, w.p1, "2026-10-08T10:00").id();
        failNext("bookings", "UPDATE", "55P03", 5);
        assertConcurrentUpdate(statusWithKey(id, "CANCELED", UUID.randomUUID().toString()));
        assertThat(attempts()).isEqualTo(1);
        assertThat(statusInDb(id)).isEqualTo("SCHEDULED");
        assertThat(count("SELECT count(*) FROM booking_status_requests")).isZero();
    }

    @Test
    @DisplayName("lock_timeout (55P03) ao agendar pelo app e ao bloquear: 409 CONCURRENT_UPDATE com corpo, SEM 2ª tentativa, nada criado")
    void lockNotAvailableOnCreateIsNotRetried() {
        failNext("bookings", "INSERT", "55P03", 5);
        assertConcurrentUpdate(clientCreate(UUID.randomUUID().toString(), newCode()));
        assertThat(attempts()).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM bookings")).isZero();

        failNext("blocks", "INSERT", "55P03", 5);
        assertConcurrentUpdate(block(w.tGA, w.shopA, w.p1, "2026-10-08T14:00", "2026-10-08T15:00"));
        assertThat(attempts()).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM blocks")).isZero();
    }

    // ------------------------------------------------------------------ 2ª tentativa lê o estado de novo

    /**
     * Roda {@code request} numa thread. A 1ª tentativa dele já leu o agendamento como SCHEDULED e
     * fica parada no trigger de booking_status_requests (gate). Nesse meio-tempo o G-A cancela
     * pela Casa (outra transação, confirmada). Solta o gate: a 1ª tentativa leva deadlock, e a 2ª,
     * numa transação nova, lê o status de novo.
     */
    private Res withOtherAgentBetweenAttempts(UUID bookingId, java.util.concurrent.Callable<Res> request) throws Exception {
        failNext("booking_status_requests", "INSERT", "40P01", 1, true);
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try (Connection gate = dataSource.getConnection(); Statement st = gate.createStatement()) {
            gate.setAutoCommit(true);
            st.execute("SELECT pg_advisory_lock(" + GATE + ")");
            Future<Res> pending = pool.submit(request);
            waitUntilSomeoneWaitsOnGate(pending);
            assertThat(statusInDb(bookingId)).isEqualTo("SCHEDULED");

            Res other = status(w.tGA, w.shopA, bookingId, "CANCELED");
            assertThat(other.status()).as(other.toString()).isEqualTo(200);

            st.execute("SELECT pg_advisory_unlock(" + GATE + ")");
            return pending.get(30, TimeUnit.SECONDS);
        } finally {
            pool.shutdownNow();
        }
    }

    private void waitUntilSomeoneWaitsOnGate(Future<Res> pending) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20);
        while (System.nanoTime() < deadline) {
            int waiting = count("SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted AND objid = " + GATE);
            if (waiting > 0) {
                return;
            }
            assertThat(pending.isDone()).as("o pedido terminou sem passar pelo gate").isFalse();
            Thread.sleep(20);
        }
        throw new AssertionError("a 1ª tentativa não chegou no gate");
    }

    private static void assertStatusChanged(Res r) {
        assertThat(r.status()).as(r.toString()).isEqualTo(409);
        assertThat(r.code()).as(r.toString()).isEqualTo("STATUS_CHANGED");
        assertThat(r.body().get("status").asInt()).isEqualTo(409);
        assertThat(r.body().get("title").asText()).isEqualTo("O status desse horário já mudou");
    }

    @Test
    @DisplayName("Mudar status: deadlock na 1ª tentativa, o G-A cancela no meio-tempo, a 2ª (transação nova) relê e dá 409 STATUS_CHANGED, não CONCURRENT_UPDATE")
    void statusRetryRereadsState() throws Exception {
        UUID id = houseBook(w.corte, w.p1, "2026-10-08T10:00").id();
        clock.setSp("2026-10-08T10:10:00");
        String key = UUID.randomUUID().toString();
        Res r = withOtherAgentBetweenAttempts(id, () -> statusWithKey(id, "COMPLETED", key));
        assertStatusChanged(r);
        // 1ª tentativa (deadlock), o cancelamento do G-A e a 2ª tentativa passaram pelo trigger.
        assertThat(attempts()).isEqualTo(3);
        assertThat(statusInDb(id)).isEqualTo("CANCELED");
        assertThat(count("SELECT count(*) FROM bookings WHERE id = '" + id + "' AND canceled_by = 'STAFF' AND completed_at IS NULL"))
                .isEqualTo(1);
        // Só a chave do G-A ficou: a do pedido recusado voltou nas duas tentativas.
        assertThat(count("SELECT count(*) FROM booking_status_requests WHERE idempotency_key = '" + key + "'")).isZero();
        assertThat(count("SELECT count(*) FROM booking_status_requests")).isEqualTo(1);
    }

    @Test
    @DisplayName("Cliente cancela: deadlock na 1ª tentativa, a Casa cancela no meio-tempo, a 2ª (transação nova) relê e dá 409 STATUS_CHANGED")
    void clientCancelRetryRereadsState() throws Exception {
        String code = newCode();
        UUID id = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T12:00", T1, code).id();
        String key = UUID.randomUUID().toString();
        Res r = withOtherAgentBetweenAttempts(id, () -> clientCancel(code, id, key));
        assertStatusChanged(r);
        assertThat(attempts()).isEqualTo(3);
        assertThat(count("SELECT count(*) FROM bookings WHERE id = '" + id + "' AND canceled_by = 'STAFF'")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM booking_status_requests WHERE idempotency_key = '" + key + "'")).isZero();
    }

    @Test
    @DisplayName("Rota sem repetição (desbloquear): deadlock que sobra vira 409 CONCURRENT_UPDATE pelo handler, nunca 500 nem VALIDATION_ERROR")
    void leftoverDeadlockIsConcurrentUpdate() {
        UUID blockId = block(w.tGA, w.shopA, w.p1, "2026-10-08T14:00", "2026-10-08T15:00").id();
        failNext("blocks", "DELETE", "40P01", 5);
        assertConcurrentUpdate(send(req(HttpMethod.DELETE, "/barbershops/" + w.shopA + "/blocks/" + blockId).token(w.tGA)));
        assertThat(attempts()).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM blocks")).isEqualTo(1);
    }

    @Test
    @DisplayName("Conflito de status de verdade segue 409 STATUS_CHANGED")
    void realStatusConflictStaysStatusChanged() {
        UUID id = houseBook(w.corte, w.p1, "2026-10-08T10:00").id();
        assertThat(status(w.tGA, w.shopA, id, "CANCELED").status()).isEqualTo(200);
        Res late = status(w.tGA, w.shopA, id, "CANCELED");
        assertThat(late.status()).isEqualTo(409);
        assertThat(late.code()).isEqualTo("STATUS_CHANGED");
    }
}
