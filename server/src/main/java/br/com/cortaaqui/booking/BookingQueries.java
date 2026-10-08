package br.com.cortaaqui.booking;

import br.com.cortaaqui.common.SpTime;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class BookingQueries {

    static final String SELECT = """
            SELECT b.id, b.barbershop_id, s.name AS barbershop_name, b.professional_id, p.name AS professional_name,
                   p.photo_url AS professional_photo_url, b.service_id, b.service_name, b.client_profile_id,
                   cp.name AS client_name, b.client_id, c.phone AS client_phone, b.source, b.status, b.start_at, b.end_at,
                   b.duration_minutes, b.price_cents, b.professional_percent, b.shop_percent, b.professional_cents,
                   b.shop_cents, b.canceled_by, b.note, b.created_at, b.request_fingerprint, b.created_by_user_id
              FROM bookings b
              JOIN barbershops s ON s.id = b.barbershop_id
              JOIN professionals p ON p.id = b.professional_id
              JOIN client_profiles cp ON cp.id = b.client_profile_id
              LEFT JOIN clients c ON c.id = cp.client_id
            """;

    private final JdbcClient db;

    public BookingQueries(JdbcClient db) {
        this.db = db;
    }

    static Instant ts(ResultSet rs, String col) throws SQLException {
        OffsetDateTime o = rs.getObject(col, OffsetDateTime.class);
        return o == null ? null : o.toInstant();
    }

    static Integer intOrNull(ResultSet rs, String col) throws SQLException {
        int v = rs.getInt(col);
        return rs.wasNull() ? null : v;
    }

    static BookingRow map(ResultSet rs, int i) throws SQLException {
        return new BookingRow(rs.getObject("id", UUID.class), rs.getObject("barbershop_id", UUID.class),
                rs.getString("barbershop_name"), rs.getObject("professional_id", UUID.class), rs.getString("professional_name"),
                rs.getString("professional_photo_url"), rs.getObject("service_id", UUID.class), rs.getString("service_name"),
                rs.getObject("client_profile_id", UUID.class), rs.getString("client_name"), rs.getObject("client_id", UUID.class),
                rs.getString("client_phone"), rs.getString("source"), rs.getString("status"), ts(rs, "start_at"),
                ts(rs, "end_at"), rs.getInt("duration_minutes"), rs.getInt("price_cents"),
                intOrNull(rs, "professional_percent"), intOrNull(rs, "shop_percent"),
                intOrNull(rs, "professional_cents"), intOrNull(rs, "shop_cents"),
                rs.getString("canceled_by"), rs.getString("note"), ts(rs, "created_at"), rs.getString("request_fingerprint"),
                rs.getObject("created_by_user_id", UUID.class));
    }

    public Optional<BookingRow> find(UUID barbershopId, UUID id) {
        return db.sql(SELECT + " WHERE b.barbershop_id = :b AND b.id = :id")
                .param("b", barbershopId).param("id", id).query(BookingQueries::map).optional();
    }

    public Optional<BookingRow> findById(UUID id) {
        return db.sql(SELECT + " WHERE b.id = :id").param("id", id).query(BookingQueries::map).optional();
    }

    public Optional<BookingRow> findByIdempotencyKey(UUID key) {
        return db.sql(SELECT + " WHERE b.idempotency_key = :k").param("k", key).query(BookingQueries::map).optional();
    }

    public List<BookingRow> forProfessional(UUID barbershopId, UUID professionalId, Instant from, Instant to) {
        return db.sql(SELECT + """
                         WHERE b.barbershop_id = :b AND b.professional_id = :p AND b.start_at < :to AND b.end_at > :from
                         ORDER BY b.start_at, b.created_at
                        """)
                .param("b", barbershopId).param("p", professionalId).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query(BookingQueries::map).list();
    }

    /**
     * Caixa (Eng. Dados): concluídos do profissional com início em [from, to). O mês é o do
     * início do atendimento em Brasília, não o da conclusão.
     */
    public List<BookingRow> completedForProfessional(UUID barbershopId, UUID professionalId, Instant from, Instant to) {
        return db.sql(SELECT + """
                         WHERE b.barbershop_id = :b AND b.professional_id = :p AND b.status = 'COMPLETED'
                           AND b.start_at >= :from AND b.start_at < :to
                         ORDER BY b.start_at, b.created_at
                        """)
                .param("b", barbershopId).param("p", professionalId).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query(BookingQueries::map).list();
    }

    /** Últimos agendamentos da ficha; {@code onlyProfessional} != null limita à agenda desse profissional. */
    public List<BookingRow> recentForProfile(UUID barbershopId, UUID profileId, UUID onlyProfessional, int limit) {
        return db.sql(SELECT + """
                         WHERE b.barbershop_id = :b AND b.client_profile_id = :cp
                           AND (CAST(:p AS uuid) IS NULL OR b.professional_id = :p)
                         ORDER BY b.start_at DESC LIMIT :lim
                        """)
                .param("b", barbershopId).param("cp", profileId).param("p", onlyProfessional).param("lim", limit)
                .query(BookingQueries::map).list();
    }

    /** Meus horários: todas as barbearias do cliente (cliente único por telefone). */
    public List<BookingRow> forClient(UUID clientId, boolean upcoming, Instant now, int limit) {
        String where = upcoming ? " WHERE b.client_id = :c AND b.end_at > :now ORDER BY b.start_at ASC LIMIT :lim"
                : " WHERE b.client_id = :c AND b.end_at <= :now ORDER BY b.start_at DESC LIMIT :lim";
        return db.sql(SELECT + where)
                .param("c", clientId).param("now", SpTime.db(now)).param("lim", limit)
                .query(BookingQueries::map).list();
    }
}
