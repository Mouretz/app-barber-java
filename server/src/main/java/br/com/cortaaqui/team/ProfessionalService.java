package br.com.cortaaqui.team;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.SpTime;
import java.time.Clock;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Profissionais (só gerente). Nunca apagados, só desativados. */
@Service
public class ProfessionalService {

    private final JdbcClient db;
    private final Access access;
    private final Professionals professionals;
    private final Clock clock;

    public ProfessionalService(JdbcClient db, Access access, Professionals professionals, Clock clock) {
        this.db = db;
        this.access = access;
        this.professionals = professionals;
        this.clock = clock;
    }

    public record ProfessionalJson(UUID id, String name, String photoUrl, boolean active, String email) {
    }

    public record ProfessionalRequest(String name, String email, String photoUrl) {
    }

    public record ProfessionalPatch(String name, String photoUrl, Boolean active) {
    }

    public List<ProfessionalJson> list(UUID barbershopId) {
        access.manager(barbershopId);
        Map<UUID, String> emails = emails(barbershopId);
        return professionals.listAll(barbershopId).stream()
                .map(p -> new ProfessionalJson(p.id(), p.name(), p.photoUrl(), p.active(), emails.get(p.id())))
                .toList();
    }

    private Map<UUID, String> emails(UUID barbershopId) {
        return db.sql("""
                        SELECT m.professional_id, u.email FROM memberships m JOIN staff_users u ON u.id = m.user_id
                         WHERE m.barbershop_id = :b AND m.professional_id IS NOT NULL
                        """)
                .param("b", barbershopId)
                .query((rs, i) -> Map.entry(rs.getObject(1, UUID.class), rs.getString(2)))
                .list().stream().collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    @Transactional
    public ProfessionalJson create(UUID barbershopId, ProfessionalRequest req) {
        access.manager(barbershopId);
        Checks.start()
                .text("name", req.name(), 1, 60, true)
                .email("email", req.email())
                .text("photoUrl", req.photoUrl(), 1, 500, false)
                .orThrow();
        UUID id = db.sql("INSERT INTO professionals (barbershop_id, name, photo_url) VALUES (:b, :n, :ph) RETURNING id")
                .param("b", barbershopId).param("n", req.name().strip()).param("ph", req.photoUrl())
                .query(UUID.class).single();
        String email = null;
        if (req.email() != null) {
            email = req.email().strip().toLowerCase(Locale.ROOT);
            // Login sem senha: o primeiro acesso/troca de senha fica fora do contrato do MVP.
            UUID userId = db.sql("""
                            INSERT INTO staff_users (name, email) VALUES (:n, :e)
                            ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
                            RETURNING id
                            """)
                    .param("n", req.name().strip()).param("e", email).query(UUID.class).single();
            int linked = db.sql("""
                            INSERT INTO memberships (barbershop_id, user_id, professional_id) VALUES (:b, :u, :p)
                            ON CONFLICT (barbershop_id, user_id) DO UPDATE SET professional_id = EXCLUDED.professional_id
                             WHERE memberships.professional_id IS NULL
                            """)
                    .param("b", barbershopId).param("u", userId).param("p", id).update();
            if (linked == 0) {
                throw ApiException.conflict(ErrorCode.EMAIL_IN_USE, "Esse e-mail já é de um profissional desta barbearia");
            }
        }
        return new ProfessionalJson(id, req.name().strip(), req.photoUrl(), true, email);
    }

    @Transactional
    public ProfessionalJson update(UUID barbershopId, UUID professionalId, ProfessionalPatch req) {
        access.manager(barbershopId);
        ProfessionalRow current = professionals.findForUpdate(barbershopId, professionalId).orElseThrow(ApiException::notFound);
        Checks.start()
                .isTrue(req.name() != null || req.photoUrl() != null || req.active() != null, "body", "informe ao menos um campo")
                .text("name", req.name(), 1, 60, false)
                .text("photoUrl", req.photoUrl(), 1, 500, false)
                .orThrow();
        boolean active = req.active() != null ? req.active() : current.active();
        if (current.active() && !active) {
            Integer future = db.sql("""
                            SELECT count(*) FROM bookings
                             WHERE barbershop_id = :b AND professional_id = :p AND status = 'SCHEDULED' AND start_at > :now
                            """)
                    .param("b", barbershopId).param("p", professionalId).param("now", SpTime.db(clock.instant()))
                    .query(Integer.class).single();
            if (future > 0) {
                throw ApiException.conflict(ErrorCode.PROFESSIONAL_HAS_FUTURE_BOOKINGS,
                        "O profissional tem horários futuros ativos; cancele antes de desativar");
            }
        }
        db.sql("""
                        UPDATE professionals SET name = :n, photo_url = :ph, active = :a,
                               deactivated_at = CASE WHEN :a THEN NULL ELSE coalesce(deactivated_at, :now) END
                         WHERE barbershop_id = :b AND id = :id
                        """)
                .param("n", req.name() != null ? req.name().strip() : current.name())
                .param("ph", req.photoUrl() != null ? req.photoUrl() : current.photoUrl())
                .param("a", active).param("now", SpTime.db(clock.instant()))
                .param("b", barbershopId).param("id", professionalId)
                .update();
        ProfessionalRow p = professionals.find(barbershopId, professionalId).orElseThrow();
        return new ProfessionalJson(p.id(), p.name(), p.photoUrl(), p.active(), emails(barbershopId).get(p.id()));
    }
}
