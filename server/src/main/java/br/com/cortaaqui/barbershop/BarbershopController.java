package br.com.cortaaqui.barbershop;

import br.com.cortaaqui.catalog.CatalogService;
import br.com.cortaaqui.catalog.ServiceRow;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import br.com.cortaaqui.team.ProfessionalPublic;
import br.com.cortaaqui.team.Professionals;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Público (app Cliente): lista e página da barbearia, só com serviços e profissionais ativos. */
@RestController
@RequestMapping("/barbershops")
public class BarbershopController {

    private final JdbcClient db;
    private final CatalogService catalog;
    private final Professionals professionals;

    public BarbershopController(JdbcClient db, CatalogService catalog, Professionals professionals) {
        this.db = db;
        this.catalog = catalog;
        this.professionals = professionals;
    }

    public record BarbershopSummary(UUID id, String name, String neighborhood, String city, String coverUrl,
                                    Integer startingPriceCents) {
    }

    public record BarbershopDetail(UUID id, String name, String neighborhood, String city, String coverUrl,
                                   Integer startingPriceCents, String address, String phone,
                                   List<ServiceRow.ServiceJson> services, List<ProfessionalPublic> professionals) {
    }

    private record Row(UUID id, String name, String neighborhood, String city, String coverUrl, Integer startingPrice,
                       String address, String phone) {
    }

    private static final String SELECT = """
            SELECT s.id, s.name, s.neighborhood, s.city, s.cover_url, s.address, s.phone,
                   (SELECT min(price_cents) FROM services sv WHERE sv.barbershop_id = s.id AND sv.active) AS starting_price
              FROM barbershops s
            """;

    private static Row map(java.sql.ResultSet rs, int i) throws java.sql.SQLException {
        int sp = rs.getInt("starting_price");
        return new Row(rs.getObject("id", UUID.class), rs.getString("name"), rs.getString("neighborhood"), rs.getString("city"),
                rs.getString("cover_url"), rs.wasNull() ? null : sp, rs.getString("address"), rs.getString("phone"));
    }

    @GetMapping
    public List<BarbershopSummary> list(@RequestParam(required = false) String q) {
        Checks.start().text("q", q, 0, 80, false).orThrow();
        String text = q == null ? "" : q.strip();
        return db.sql(SELECT + """
                         WHERE :q = '' OR unaccent(lower(s.name)) LIKE '%' || unaccent(lower(:q)) || '%'
                            OR unaccent(lower(s.neighborhood)) LIKE '%' || unaccent(lower(:q)) || '%'
                         ORDER BY s.name
                        """)
                .param("q", text).query(BarbershopController::map).list().stream()
                .map(r -> new BarbershopSummary(r.id(), r.name(), r.neighborhood(), r.city(), r.coverUrl(), r.startingPrice()))
                .toList();
    }

    @GetMapping("/{barbershopId}")
    public BarbershopDetail detail(@PathVariable UUID barbershopId) {
        Row r = db.sql(SELECT + " WHERE s.id = :id").param("id", barbershopId).query(BarbershopController::map).optional()
                .orElseThrow(ApiException::notFound);
        return new BarbershopDetail(r.id(), r.name(), r.neighborhood(), r.city(), r.coverUrl(), r.startingPrice(), r.address(),
                r.phone(), catalog.listActive(barbershopId).stream().map(ServiceRow::json).toList(),
                professionals.listActive(barbershopId).stream().map(p -> new ProfessionalPublic(p.id(), p.name(), p.photoUrl()))
                        .toList());
    }
}
