package br.com.cortaaqui.catalog;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Serviços e preços (só gerente). Mudar preço ou duração não mexe em agendamento já criado. */
@Service
public class CatalogService {

    /** Regra do PO (08/10): duração só em múltiplos de 30 (30, 60, 90...), até 8 h. 45 dá 422. */
    static final int MIN_DURATION = 30;
    static final int MAX_DURATION = 480;
    static final int DURATION_STEP = 30;

    private static final String COLS = "id, barbershop_id, name, duration_minutes, price_cents, active";

    private final JdbcClient db;
    private final Access access;

    public CatalogService(JdbcClient db, Access access) {
        this.db = db;
        this.access = access;
    }

    public record ServiceRequest(String name, Integer durationMinutes, Integer priceCents) {
    }

    public record ServicePatch(String name, Integer durationMinutes, Integer priceCents, Boolean active) {
    }

    static ServiceRow map(ResultSet rs, int i) throws SQLException {
        return new ServiceRow(rs.getObject("id", UUID.class), rs.getObject("barbershop_id", UUID.class), rs.getString("name"),
                rs.getInt("duration_minutes"), rs.getInt("price_cents"), rs.getBoolean("active"));
    }

    public Optional<ServiceRow> find(UUID barbershopId, UUID id) {
        return db.sql("SELECT " + COLS + " FROM services WHERE barbershop_id = :b AND id = :id")
                .param("b", barbershopId).param("id", id).query(CatalogService::map).optional();
    }

    public List<ServiceRow> listActive(UUID barbershopId) {
        return db.sql("SELECT " + COLS + " FROM services WHERE barbershop_id = :b AND active ORDER BY price_cents, name")
                .param("b", barbershopId).query(CatalogService::map).list();
    }

    public List<ServiceRow.ServiceJson> list(UUID barbershopId) {
        access.manager(barbershopId);
        return db.sql("SELECT " + COLS + " FROM services WHERE barbershop_id = :b ORDER BY active DESC, name")
                .param("b", barbershopId).query(CatalogService::map).list().stream().map(ServiceRow::json).toList();
    }

    @Transactional
    public ServiceRow.ServiceJson create(UUID barbershopId, ServiceRequest req) {
        access.manager(barbershopId);
        Checks.start()
                .text("name", req.name(), 1, 60, true)
                .required("durationMinutes", req.durationMinutes()).rangeStep("durationMinutes", req.durationMinutes(), MIN_DURATION, MAX_DURATION, DURATION_STEP)
                .required("priceCents", req.priceCents()).range("priceCents", req.priceCents(), 0, Integer.MAX_VALUE)
                .orThrow();
        return db.sql("INSERT INTO services (barbershop_id, name, duration_minutes, price_cents) VALUES (:b, :n, :d, :p) RETURNING " + COLS)
                .param("b", barbershopId).param("n", req.name().strip()).param("d", req.durationMinutes()).param("p", req.priceCents())
                .query(CatalogService::map).single().json();
    }

    @Transactional
    public ServiceRow.ServiceJson update(UUID barbershopId, UUID serviceId, ServicePatch req) {
        access.manager(barbershopId);
        ServiceRow current = find(barbershopId, serviceId).orElseThrow(ApiException::notFound);
        Checks.start()
                .isTrue(req.name() != null || req.durationMinutes() != null || req.priceCents() != null || req.active() != null,
                        "body", "informe ao menos um campo")
                .text("name", req.name(), 1, 60, false)
                .rangeStep("durationMinutes", req.durationMinutes(), MIN_DURATION, MAX_DURATION, DURATION_STEP)
                .range("priceCents", req.priceCents(), 0, Integer.MAX_VALUE)
                .orThrow();
        return db.sql("UPDATE services SET name = :n, duration_minutes = :d, price_cents = :p, active = :a "
                        + "WHERE barbershop_id = :b AND id = :id RETURNING " + COLS)
                .param("n", req.name() != null ? req.name().strip() : current.name())
                .param("d", req.durationMinutes() != null ? req.durationMinutes() : current.durationMinutes())
                .param("p", req.priceCents() != null ? req.priceCents() : current.priceCents())
                .param("a", req.active() != null ? req.active() : current.active())
                .param("b", barbershopId).param("id", serviceId)
                .query(CatalogService::map).single().json();
    }
}
