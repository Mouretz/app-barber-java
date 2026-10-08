package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import br.com.cortaaqui.support.DomainTest;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.dao.DataIntegrityViolationException;

/** A trava no banco: INSERT direto, sem passar pelo serviço. */
class BookingConstraintsIT extends DomainTest {

    @Test
    @DisplayName("CT-03-01 sobreposição parcial 10:15–10:45 sobre 10:00–10:30 é recusada pelo Postgres")
    void partialOverlapRefused() {
        insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED");
        assertThatThrownBy(() -> insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:15", 30, "SCHEDULED"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("ex_agenda_sem_sobreposicao");
    }

    @Test
    @DisplayName("CT-03-03 horário contido (10:15–10:45 dentro de 10:00–11:00) é recusado")
    void containedRefused() {
        insertBookingDirect(w.shopA, w.p1, w.combo, "2026-10-08T10:00", 60, "SCHEDULED");
        assertThatThrownBy(() -> insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:15", 30, "SCHEDULED"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("CT-03-04 encostados são aceitos: intervalo [início, fim)")
    void adjacentAccepted() {
        insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED");
        assertThatCode(() -> {
            insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:30", 30, "SCHEDULED");
            insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T09:30", 30, "SCHEDULED");
        }).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("CT-03-05 a trava é por profissional: P2 no mesmo horário de P1 é aceito")
    void perProfessional() {
        insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED");
        assertThatCode(() -> insertBookingDirect(w.shopA, w.p2, w.corte, "2026-10-08T10:00", 30, "SCHEDULED"))
                .doesNotThrowAnyException();
    }

    @ParameterizedTest(name = "existente {0}: agendamento novo por cima recusado = {1}")
    @DisplayName("CT-03-06 / CT-03-10 / CT-03-11 SCHEDULED, COMPLETED e bloqueio barram agendamento novo; NO_SHOW e CANCELED não")
    @CsvSource({"SCHEDULED, true", "COMPLETED, true", "BLOCK, true", "NO_SHOW, false", "CANCELED, false"})
    void whatOccupies(String existing, boolean refused) {
        if ("BLOCK".equals(existing)) {
            insertBlockDirect(w.shopA, w.p1, "2026-10-08T10:00", "2026-10-08T10:30");
        } else {
            insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, existing);
        }
        Runnable booking = () -> insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:15", 30, "SCHEDULED");
        if (refused) {
            assertThatThrownBy(booking::run).isInstanceOf(DataIntegrityViolationException.class)
                    .hasMessageContaining("BLOCK".equals(existing) ? "ck_bookings_not_on_block" : "ex_agenda_sem_sobreposicao");
        } else {
            assertThatCode(booking::run).doesNotThrowAnyException();
        }
        // Bloqueio por cima: agendamento nunca impede (decisão do PO); outro bloqueio impede.
        Runnable block = () -> insertBlockDirect(w.shopA, w.p1, "2026-10-08T10:00", "2026-10-08T11:00");
        if ("BLOCK".equals(existing)) {
            assertThatThrownBy(block::run).isInstanceOf(DataIntegrityViolationException.class)
                    .hasMessageContaining("ex_bloqueio_sem_sobreposicao");
        } else {
            assertThatCode(block::run).doesNotThrowAnyException();
        }
    }

    @Test
    @DisplayName("Bloqueio x bloqueio recusado (encostado pode); bloqueio em cima de agendamento é estado permitido no banco")
    void blocksOverlapAndCoverBookings() {
        UUID b = insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED");
        insertBlockDirect(w.shopA, w.p1, "2026-10-08T09:00", "2026-10-08T11:00");
        assertThatThrownBy(() -> insertBlockDirect(w.shopA, w.p1, "2026-10-08T10:30", "2026-10-08T12:00"))
                .isInstanceOf(DataIntegrityViolationException.class).hasMessageContaining("ex_bloqueio_sem_sobreposicao");
        assertThatCode(() -> insertBlockDirect(w.shopA, w.p1, "2026-10-08T11:00", "2026-10-08T12:00"))
                .doesNotThrowAnyException();
        assertThatCode(() -> insertBlockDirect(w.shopA, w.p2, "2026-10-08T09:00", "2026-10-08T11:00"))
                .doesNotThrowAnyException();
        assertThat(statusInDb(b)).isEqualTo("SCHEDULED");
        // o agendamento debaixo do bloqueio ainda muda de status normalmente
        db.sql("UPDATE bookings SET status = 'CANCELED', canceled_by = 'STAFF' WHERE id = :id").param("id", b).update();
        assertThat(statusInDb(b)).isEqualTo("CANCELED");
        // outro profissional não é afetado pelo bloqueio do P1
        assertThatCode(() -> insertBookingDirect(w.shopA, w.gp, w.corte, "2026-10-08T10:00", 30, "SCHEDULED"))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("Marcar falta ou cancelar libera o horário para outro agendamento; desbloquear também")
    void statusChangeFreesOccupancy() {
        UUID b = insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED");
        db.sql("UPDATE bookings SET status = 'NO_SHOW' WHERE id = :id").param("id", b).update();
        assertThatCode(() -> insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED"))
                .doesNotThrowAnyException();
        UUID block = insertBlockDirect(w.shopA, w.p1, "2026-10-08T11:00", "2026-10-08T12:00");
        assertThatThrownBy(() -> insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T11:00", 30, "SCHEDULED"))
                .isInstanceOf(DataIntegrityViolationException.class);
        db.sql("DELETE FROM blocks WHERE id = :id").param("id", block).update();
        assertThatCode(() -> insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T11:00", 30, "SCHEDULED"))
                .doesNotThrowAnyException();
    }

    @ParameterizedTest(name = "{0} -> qualquer outro é recusado no banco")
    @DisplayName("CT-00-01 status final não muda nem no UPDATE direto (trigger)")
    @ValueSource(strings = {"COMPLETED", "NO_SHOW", "CANCELED"})
    void finalStatusIsFinal(String from) {
        UUID b = insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, from);
        for (String to : List.of("SCHEDULED", "COMPLETED", "NO_SHOW", "CANCELED")) {
            if (to.equals(from)) {
                continue;
            }
            assertThatThrownBy(() -> db.sql("""
                            UPDATE bookings SET status = :to,
                                   canceled_by = CASE WHEN :to = 'CANCELED' THEN 'STAFF' END,
                                   professional_percent = CASE WHEN :to = 'COMPLETED' THEN 60 END,
                                   shop_percent = CASE WHEN :to = 'COMPLETED' THEN 40 END,
                                   professional_cents = CASE WHEN :to = 'COMPLETED' THEN 600 END,
                                   shop_cents = CASE WHEN :to = 'COMPLETED' THEN 400 END
                             WHERE id = :id
                            """).param("to", to).param("id", b).update())
                    .as(from + " -> " + to)
                    .isInstanceOf(DataIntegrityViolationException.class);
        }
        assertThat(statusInDb(b)).isEqualTo(from);
    }

    @Test
    @DisplayName("Concluído sempre com % e centavos que somam o preço (CHECK no banco)")
    void completedSplitMustSum() {
        UUID b = insertBookingDirect(w.shopA, w.p1, w.corte, "2026-10-08T10:00", 30, "SCHEDULED");
        assertThatThrownBy(() -> db.sql("""
                        UPDATE bookings SET status = 'COMPLETED', professional_percent = 60, shop_percent = 40,
                               professional_cents = 600, shop_cents = 300 WHERE id = :id
                        """).param("id", b).update())
                .isInstanceOf(DataIntegrityViolationException.class);
        assertThatThrownBy(() -> db.sql("UPDATE bookings SET status = 'COMPLETED' WHERE id = :id").param("id", b).update())
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("CT-17-14 telefone único (normalizado) e com formato só de dígitos 55 + 10/11")
    void phoneConstraints() {
        db.sql("INSERT INTO clients (phone) VALUES ('5511987654321')").update();
        assertThatThrownBy(() -> db.sql("INSERT INTO clients (phone) VALUES ('5511987654321')").update())
                .isInstanceOf(DataIntegrityViolationException.class).hasMessageContaining("uk_clients_phone");
        assertThatThrownBy(() -> db.sql("INSERT INTO clients (phone) VALUES ('11987654321')").update())
                .isInstanceOf(DataIntegrityViolationException.class).hasMessageContaining("ck_clients_phone_format");
        assertThatThrownBy(() -> db.sql("INSERT INTO clients (phone) VALUES ('+5511987654321')").update())
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("CT-00-29 toda tabela de negócio tem barbershop_id NOT NULL com FK")
    void everyBusinessTableHasTenant() {
        // Globais por decisão de modelo: login (uma pessoa, papéis por barbearia), sessão e cliente por telefone.
        List<String> global = List.of("barbershops", "staff_users", "staff_sessions", "clients", "flyway_schema_history");
        List<String> tables = db.sql("""
                        SELECT table_name FROM information_schema.tables
                         WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
                        """).query(String.class).list();
        assertThat(tables).contains("bookings", "blocks", "agenda_occupancy", "client_profiles", "memberships");
        for (String t : tables) {
            if (global.contains(t)) {
                continue;
            }
            Boolean notNull = db.sql("""
                            SELECT is_nullable = 'NO' FROM information_schema.columns
                             WHERE table_schema = 'public' AND table_name = :t AND column_name = 'barbershop_id'
                            """).param("t", t).query(Boolean.class).optional().orElse(false);
            assertThat(notNull).as(t + ".barbershop_id NOT NULL").isTrue();
            Integer fks = db.sql("""
                            SELECT count(*) FROM pg_constraint c
                              JOIN pg_class r ON r.oid = c.conrelid
                              JOIN pg_attribute a ON a.attrelid = r.oid AND a.attnum = ANY (c.conkey)
                             WHERE c.contype = 'f' AND r.relname = :t AND a.attname = 'barbershop_id'
                            """).param("t", t).query(Integer.class).single();
            assertThat(fks).as(t + ".barbershop_id com FK").isPositive();
        }
    }

    @Test
    @DisplayName("CT-00-41 telefone único, UNIQUE (barbershop_id, client_id) na ficha e (barbershop_id, user_id) no vínculo")
    void uniqueConstraints() {
        List<String> names = db.sql("SELECT conname FROM pg_constraint WHERE contype = 'u'").query(String.class).list();
        assertThat(names).contains("uk_clients_phone", "uk_client_profiles_client", "uk_memberships_user");
        assertThat(count("""
                SELECT count(*) FROM pg_constraint
                 WHERE conname IN ('ex_agenda_sem_sobreposicao', 'ex_bloqueio_sem_sobreposicao') AND contype = 'x'
                """)).isEqualTo(2);
    }

    @Test
    @DisplayName("CT-00-10 senha gravada é hash BCrypt, nunca texto puro")
    void passwordIsBcrypt() {
        List<String> hashes = db.sql("SELECT password_hash FROM staff_users WHERE password_hash IS NOT NULL")
                .query(String.class).list();
        assertThat(hashes).isNotEmpty().allSatisfy(h -> assertThat(h).startsWith("$2").doesNotContain("senha"));
        assertThatThrownBy(() -> db.sql("INSERT INTO staff_users (name, email, password_hash) VALUES ('X', 'x@x.test', 'texto-puro')").update())
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
