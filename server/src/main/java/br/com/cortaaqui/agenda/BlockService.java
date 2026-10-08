package br.com.cortaaqui.agenda;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.common.AgendaLock;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.team.Professionals;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Bloqueio: intervalo dentro de um dia, início e fim na grade de 30 min (00:00 do dia seguinte
 * conta como fim do mesmo dia). Passa pela mesma trava dos agendamentos (EXCLUDE).
 * Profissional bloqueia e desbloqueia só a própria agenda; gerente, qualquer uma.
 */
@Service
public class BlockService {

    private final JdbcClient db;
    private final Access access;
    private final Professionals professionals;
    private final Clock clock;
    private final AgendaLock agendaLock;

    public BlockService(JdbcClient db, Access access, Professionals professionals, Clock clock, AgendaLock agendaLock) {
        this.db = db;
        this.access = access;
        this.professionals = professionals;
        this.clock = clock;
        this.agendaLock = agendaLock;
    }

    public record BlockRequest(UUID professionalId, OffsetDateTime startAt, OffsetDateTime endAt, String reason) {
    }

    public record Block(UUID id, UUID professionalId, OffsetDateTime startAt, OffsetDateTime endAt, String reason) {
    }

    @Transactional
    public Block create(UUID barbershopId, BlockRequest req) {
        MembershipView m = access.member(barbershopId);
        Checks.start().required("professionalId", req.professionalId()).orThrow();
        access.requireSelfOrManager(m, req.professionalId());
        Checks.start().required("startAt", req.startAt()).required("endAt", req.endAt())
                .text("reason", req.reason(), 0, 120, false).orThrow();
        Instant start = req.startAt().toInstant();
        Instant end = req.endAt().toInstant();
        Checks.start()
                .isTrue(SpTime.onGrid(start), "startAt", "o início tem que cair em :00 ou :30")
                .isTrue(SpTime.onGrid(end), "endAt", "o fim tem que cair em :00 ou :30")
                .orThrow();
        if (!end.isAfter(start)) {
            throw ApiException.invalidField("endAt", "o fim tem que ser depois do início");
        }
        LocalDate day = LocalDate.ofInstant(start, SpTime.ZONE);
        if (end.isAfter(SpTime.startOfDay(day.plusDays(1)))) {
            throw ApiException.invalidField("endAt", "o bloqueio não atravessa a meia-noite");
        }
        if (!end.isAfter(clock.instant())) {
            throw ApiException.unprocessable(ErrorCode.SLOT_IN_PAST, "Esse horário já terminou");
        }
        professionals.find(barbershopId, req.professionalId()).filter(p -> p.active()).orElseThrow(ApiException::notFound);
        // Mesma fila da agenda dos agendamentos (AgendaLock): sem deadlock no EXCLUDE entre
        // bloqueios sobrepostos, e bloqueio x agendamento novo vira "quem chegou antes vale".
        agendaLock.lock(barbershopId, req.professionalId());
        // Bloquear nunca tira o que já está marcado (decisão do PO): o bloqueio entra mesmo em cima
        // de agendamento ativo, que fica e sai com overlapsBlock = true na agenda da Casa, para o
        // profissional resolver (atender ou cancelar). Bloqueio em cima de outro bloqueio do mesmo
        // profissional: o EXCLUDE ex_bloqueio_sem_sobreposicao recusa (409 SLOT_TAKEN).
        return db.sql("""
                        INSERT INTO blocks (barbershop_id, professional_id, start_at, end_at, reason, created_by_user_id)
                        VALUES (:b, :p, :s, :e, :r, :u)
                        RETURNING id, professional_id, start_at, end_at, reason
                        """)
                .param("b", barbershopId).param("p", req.professionalId()).param("s", SpTime.db(start))
                .param("e", SpTime.db(end)).param("r", req.reason()).param("u", access.principal().userId())
                .query((rs, i) -> map(rs)).single();
    }

    @Transactional
    public void delete(UUID barbershopId, UUID blockId) {
        MembershipView m = access.member(barbershopId);
        UUID professionalId = db.sql("SELECT professional_id FROM blocks WHERE barbershop_id = :b AND id = :id")
                .param("b", barbershopId).param("id", blockId).query(UUID.class).optional()
                .orElseThrow(ApiException::notFound);
        access.requireSelfOrManager(m, professionalId);
        // Só o bloqueio sai. Nenhuma marcação é tocada; overlapsBlock é recalculado na próxima leitura.
        db.sql("DELETE FROM blocks WHERE barbershop_id = :b AND id = :id").param("b", barbershopId).param("id", blockId).update();
    }

    public List<Block> forProfessional(UUID barbershopId, UUID professionalId, Instant from, Instant to) {
        return db.sql("""
                        SELECT id, professional_id, start_at, end_at, reason FROM blocks
                         WHERE barbershop_id = :b AND professional_id = :p AND start_at < :to AND end_at > :from
                         ORDER BY start_at
                        """)
                .param("b", barbershopId).param("p", professionalId).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query((rs, i) -> map(rs)).list();
    }

    private static Block map(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Block(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class),
                SpTime.sp(rs.getObject(3, OffsetDateTime.class).toInstant()),
                SpTime.sp(rs.getObject(4, OffsetDateTime.class).toInstant()), rs.getString(5));
    }
}
