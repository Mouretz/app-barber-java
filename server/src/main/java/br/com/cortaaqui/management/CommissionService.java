package br.com.cortaaqui.management;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.Problem;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Gerência das % (história 20). Só o gerente lê e troca.
 *
 * <p>Onde fica gravado (colunas do domínio do Back-end, sem tabela nova):
 * <ul>
 *   <li>padrão da casa: {@code barbershops.default_professional_percent} (60 ao criar);</li>
 *   <li>% própria: {@code professionals.professional_percent} (NULL = usa o padrão).</li>
 * </ul>
 * Guardamos só a % do profissional; a da casa é sempre 100 − ela, então a soma nunca sai de 100.
 * A troca vale só para o que for concluído depois: na conclusão a % é copiada para o agendamento
 * ({@code bookings.professional_percent}), e o caixa lê de lá.
 */
@Service
public class CommissionService {

    private final JdbcClient db;
    private final Access access;

    public CommissionService(JdbcClient db, Access access) {
        this.db = db;
        this.access = access;
    }

    /** CommissionSplit do contrato. Integer (e não int) para "campo faltando" virar 422, e não 0. */
    public record Split(Integer shopPercent, Integer professionalPercent) {

        static Split ofProfessional(int professionalPercent) {
            return new Split(100 - professionalPercent, professionalPercent);
        }
    }

    /** Item de {@code professionals}: professionalId + CommissionSplit (allOf no contrato, achatado no JSON). */
    public record ProfessionalSplit(UUID professionalId, Integer shopPercent, Integer professionalPercent) {
    }

    /** CommissionSettings do contrato. {@code default} é palavra reservada em Java, por isso o nome do campo muda. */
    public record Settings(@JsonProperty("default") Split defaultSplit, List<ProfessionalSplit> professionals) {
    }

    public Settings get(UUID barbershopId) {
        access.manager(barbershopId);
        return read(barbershopId);
    }

    @Transactional
    public Settings replace(UUID barbershopId, Settings req) {
        access.manager(barbershopId);
        validate(barbershopId, req);
        // Trava a barbearia: dois PUT ao mesmo tempo não se misturam (um termina, o outro vem depois).
        db.sql("SELECT id FROM barbershops WHERE id = :b FOR UPDATE").param("b", barbershopId).query(UUID.class).single();
        db.sql("UPDATE barbershops SET default_professional_percent = :p WHERE id = :b")
                .param("p", req.defaultSplit().professionalPercent()).param("b", barbershopId).update();
        // PUT troca tudo: quem não veio na lista volta a usar o padrão.
        db.sql("UPDATE professionals SET professional_percent = NULL WHERE barbershop_id = :b AND professional_percent IS NOT NULL")
                .param("b", barbershopId).update();
        for (ProfessionalSplit p : req.professionals()) {
            db.sql("UPDATE professionals SET professional_percent = :pct WHERE barbershop_id = :b AND id = :id")
                    .param("pct", p.professionalPercent()).param("b", barbershopId).param("id", p.professionalId()).update();
        }
        return read(barbershopId);
    }

    private Settings read(UUID barbershopId) {
        int def = db.sql("SELECT default_professional_percent FROM barbershops WHERE id = :b")
                .param("b", barbershopId).query(Integer.class).single();
        List<ProfessionalSplit> own = db.sql("""
                        SELECT id, professional_percent FROM professionals
                         WHERE barbershop_id = :b AND professional_percent IS NOT NULL
                         ORDER BY name, id
                        """)
                .param("b", barbershopId)
                .query((rs, i) -> {
                    int pct = rs.getInt(2);
                    return new ProfessionalSplit(rs.getObject(1, UUID.class), 100 - pct, pct);
                })
                .list();
        return new Settings(Split.ofProfessional(def), own);
    }

    /**
     * Primeiro o formato (campo faltando, fora de 0..100, profissional que não é da barbearia,
     * repetido): 422 VALIDATION_ERROR. Depois a soma: 422 COMMISSION_SUM_INVALID.
     * Nada é gravado se qualquer item falhar.
     */
    private void validate(UUID barbershopId, Settings req) {
        List<Problem.FieldMessage> format = new ArrayList<>();
        List<Problem.FieldMessage> sums = new ArrayList<>();
        if (req == null || req.defaultSplit() == null) {
            format.add(new Problem.FieldMessage("default", "obrigatório"));
        } else {
            checkSplit("default", req.defaultSplit().shopPercent(), req.defaultSplit().professionalPercent(), format, sums);
        }
        if (req == null || req.professionals() == null) {
            format.add(new Problem.FieldMessage("professionals", "obrigatório"));
        } else {
            Set<UUID> seen = new HashSet<>();
            for (int i = 0; i < req.professionals().size(); i++) {
                ProfessionalSplit p = req.professionals().get(i);
                String f = "professionals[" + i + "]";
                if (p == null) {
                    format.add(new Problem.FieldMessage(f, "obrigatório"));
                    continue;
                }
                if (p.professionalId() == null) {
                    format.add(new Problem.FieldMessage(f + ".professionalId", "obrigatório"));
                } else if (!seen.add(p.professionalId())) {
                    format.add(new Problem.FieldMessage(f + ".professionalId", "profissional repetido"));
                } else if (!belongs(barbershopId, p.professionalId())) {
                    format.add(new Problem.FieldMessage(f + ".professionalId", "profissional não encontrado nesta barbearia"));
                }
                checkSplit(f, p.shopPercent(), p.professionalPercent(), format, sums);
            }
        }
        if (!format.isEmpty()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.VALIDATION_ERROR, "Dados inválidos", null, format);
        }
        if (!sums.isEmpty()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.COMMISSION_SUM_INVALID,
                    "A % do profissional e a da casa precisam somar 100", null, sums);
        }
    }

    private static void checkSplit(String field, Integer shop, Integer professional, List<Problem.FieldMessage> format,
                                   List<Problem.FieldMessage> sums) {
        boolean ok = true;
        if (shop == null) {
            format.add(new Problem.FieldMessage(field + ".shopPercent", "obrigatório"));
            ok = false;
        } else if (shop < 0 || shop > 100) {
            format.add(new Problem.FieldMessage(field + ".shopPercent", "deve estar entre 0 e 100"));
            ok = false;
        }
        if (professional == null) {
            format.add(new Problem.FieldMessage(field + ".professionalPercent", "obrigatório"));
            ok = false;
        } else if (professional < 0 || professional > 100) {
            format.add(new Problem.FieldMessage(field + ".professionalPercent", "deve estar entre 0 e 100"));
            ok = false;
        }
        if (ok && shop + professional != 100) {
            sums.add(new Problem.FieldMessage(field, "soma " + (shop + professional) + "; precisa ser 100"));
        }
    }

    private boolean belongs(UUID barbershopId, UUID professionalId) {
        return db.sql("SELECT EXISTS (SELECT 1 FROM professionals WHERE barbershop_id = :b AND id = :id)")
                .param("b", barbershopId).param("id", professionalId).query(Boolean.class).single();
    }
}
