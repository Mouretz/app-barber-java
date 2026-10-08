package br.com.cortaaqui.team;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Acesso aos profissionais, sempre filtrando pela barbearia. */
@Repository
public class Professionals {

    private static final String COLS = "id, barbershop_id, name, photo_url, active, professional_percent";

    private final JdbcClient db;

    public Professionals(JdbcClient db) {
        this.db = db;
    }

    static ProfessionalRow map(ResultSet rs, int i) throws SQLException {
        return new ProfessionalRow(rs.getObject("id", UUID.class), rs.getObject("barbershop_id", UUID.class),
                rs.getString("name"), rs.getString("photo_url"), rs.getBoolean("active"),
                pct(rs));
    }

    private static Integer pct(ResultSet rs) throws SQLException {
        int v = rs.getInt("professional_percent");
        return rs.wasNull() ? null : v;
    }

    public Optional<ProfessionalRow> find(UUID barbershopId, UUID id) {
        return db.sql("SELECT " + COLS + " FROM professionals WHERE barbershop_id = :b AND id = :id")
                .param("b", barbershopId).param("id", id).query(Professionals::map).optional();
    }

    /**
     * Ativo, com trava compartilhada: a desativação (FOR UPDATE) espera quem está agendando,
     * e quem agenda espera a desativação. Assim não nasce agendamento para quem acabou de ser desativado.
     */
    public Optional<ProfessionalRow> findActiveForBooking(UUID barbershopId, UUID id) {
        return db.sql("SELECT " + COLS + " FROM professionals WHERE barbershop_id = :b AND id = :id AND active FOR SHARE")
                .param("b", barbershopId).param("id", id).query(Professionals::map).optional();
    }

    public Optional<ProfessionalRow> findForUpdate(UUID barbershopId, UUID id) {
        return db.sql("SELECT " + COLS + " FROM professionals WHERE barbershop_id = :b AND id = :id FOR UPDATE")
                .param("b", barbershopId).param("id", id).query(Professionals::map).optional();
    }

    public List<ProfessionalRow> listActive(UUID barbershopId) {
        return db.sql("SELECT " + COLS + " FROM professionals WHERE barbershop_id = :b AND active ORDER BY name, id")
                .param("b", barbershopId).query(Professionals::map).list();
    }

    public List<ProfessionalRow> listAll(UUID barbershopId) {
        return db.sql("SELECT " + COLS + " FROM professionals WHERE barbershop_id = :b ORDER BY active DESC, name, id")
                .param("b", barbershopId).query(Professionals::map).list();
    }
}
