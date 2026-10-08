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

    /**
     * Vínculo que ainda dá acesso à Casa (regra do PO, 08/10): gerente, ou profissional ativo.
     * A desativação é por barbearia: o vínculo fica no banco (histórico e reativação). Sem nenhum
     * vínculo assim, login e token dão 401 ({@link AuthService}); com vínculo ativo em outra
     * barbearia, só a barbearia onde foi desativado recusa (403, {@link #member}). Use com {@code memberships m}.
     */
    public static final String USABLE_MEMBERSHIP = """
            (m.is_manager OR EXISTS (SELECT 1 FROM professionals pa
                                      WHERE pa.id = m.professional_id AND pa.active))""";

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

    /**
     * Qualquer vínculo com a barbearia. Sem vínculo: 404. Profissional desativado nesta barbearia
     * (e que não é gerente dela): 403 (regra do PO, 08/10: a desativação é por barbearia).
     */
    public MembershipView member(UUID barbershopId) {
        StaffPrincipal p = principal();
        record Row(MembershipView view, boolean usable) {
        }
        Row row = db.sql("SELECT m.barbershop_id, b.name, m.is_manager, m.professional_id, " + USABLE_MEMBERSHIP + " AS usable"
                        + " FROM memberships m JOIN barbershops b ON b.id = m.barbershop_id"
                        + " WHERE m.barbershop_id = :b AND m.user_id = :u")
                .param("b", barbershopId).param("u", p.userId())
                .query((rs, i) -> new Row(new MembershipView(rs.getObject(1, UUID.class), rs.getString(2), rs.getBoolean(3),
                        rs.getObject(4, UUID.class)), rs.getBoolean(5)))
                .optional()
                .orElseThrow(ApiException::notFound);
        if (!row.usable()) {
            // Desativado nesta barbearia, mas com vínculo ativo em outra (senão o token já deu 401):
            // aqui ele não entra mais. Mesmo corpo das outras recusas de papel.
            throw ApiException.forbidden();
        }
        return row.view();
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
