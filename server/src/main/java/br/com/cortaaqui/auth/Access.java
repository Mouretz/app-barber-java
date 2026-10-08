package br.com.cortaaqui.auth;

import br.com.cortaaqui.common.ApiException;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * Checagem de vínculo e papel por barbearia. A barbearia vem da rota, mas o papel vem do banco,
 * nunca do corpo ou da query: sem vínculo = 404 (não revela que existe), papel errado = 403.
 */
@Component
public class Access {

    private final JdbcClient db;

    public Access(JdbcClient db) {
        this.db = db;
    }

    public StaffPrincipal principal() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof StaffPrincipal p) {
            return p;
        }
        throw ApiException.unauthorized();
    }

    /** Qualquer vínculo com a barbearia. */
    public MembershipView member(UUID barbershopId) {
        StaffPrincipal p = principal();
        return db.sql("""
                        SELECT m.barbershop_id, b.name, m.is_manager, m.professional_id
                          FROM memberships m JOIN barbershops b ON b.id = m.barbershop_id
                         WHERE m.barbershop_id = :b AND m.user_id = :u
                        """)
                .param("b", barbershopId).param("u", p.userId())
                .query((rs, i) -> new MembershipView(rs.getObject(1, UUID.class), rs.getString(2), rs.getBoolean(3),
                        rs.getObject(4, UUID.class)))
                .optional()
                .orElseThrow(ApiException::notFound);
    }

    /** Só gerente. */
    public MembershipView manager(UUID barbershopId) {
        MembershipView m = member(barbershopId);
        if (!m.manager()) {
            throw ApiException.forbidden();
        }
        return m;
    }

    /** Gerente, ou o próprio profissional. */
    public void requireSelfOrManager(MembershipView m, UUID professionalId) {
        if (!m.canActOn(professionalId)) {
            throw ApiException.forbidden();
        }
    }
}
