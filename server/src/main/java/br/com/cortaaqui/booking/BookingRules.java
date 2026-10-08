package br.com.cortaaqui.booking;

import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.team.ScheduleService;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * Regras de horário, iguais para os livres e para a marcação (o app nunca calcula).
 * <ul>
 *   <li>Grade de 30 min.</li>
 *   <li>Janela de 14 dias contando hoje, em São Paulo, para todo mundo.</li>
 *   <li>App do cliente: começa com pelo menos 30 min de antecedência.</li>
 *   <li>Casa (STAFF/COUNTER): pode o slot de 30 min em andamento; o que já terminou é SLOT_IN_PAST.</li>
 *   <li>O serviço inteiro cabe numa janela do expediente e não bate com folga.</li>
 * </ul>
 * O conflito com outro agendamento ou bloqueio fica com a constraint do banco.
 */
@Component
public class BookingRules {

    public static final Duration CLIENT_MIN_NOTICE = Duration.ofMinutes(30);
    public static final Duration GRID = Duration.ofMinutes(SpTime.GRID_MINUTES);

    private final ScheduleService schedule;
    private final Clock clock;

    public BookingRules(ScheduleService schedule, Clock clock) {
        this.schedule = schedule;
        this.clock = clock;
    }

    public enum Actor { CLIENT, STAFF }

    public void requireDateInWindow(LocalDate date, String field) {
        if (!SpTime.insideBookingWindow(date, clock)) {
            throw new ApiException(org.springframework.http.HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.DATE_OUT_OF_RANGE,
                    "Dia fora da agenda (hoje até hoje + 13)", null,
                    List.of(new br.com.cortaaqui.common.Problem.FieldMessage(field, "fora da janela de 14 dias")));
        }
    }

    /** Confere tudo menos o conflito (que é do banco). */
    public void check(Actor actor, UUID professionalId, Instant start, int durationMinutes) {
        if (!SpTime.onGrid(start)) {
            throw ApiException.invalidField("startAt", "o horário tem que cair em :00 ou :30");
        }
        LocalDate date = LocalDate.ofInstant(start, SpTime.ZONE);
        requireDateInWindow(date, "startAt");
        Instant now = clock.instant();
        if (actor == Actor.CLIENT) {
            if (start.isBefore(now.plus(CLIENT_MIN_NOTICE))) {
                throw ApiException.unprocessable(ErrorCode.TOO_SOON, "Precisa de pelo menos 30 minutos de antecedência");
            }
        } else if (!start.plus(GRID).isAfter(now)) {
            throw ApiException.unprocessable(ErrorCode.SLOT_IN_PAST, "Esse horário já terminou");
        }
        Instant end = start.plus(Duration.ofMinutes(durationMinutes));
        if (!fitsWorkingHours(professionalId, date, start, end)) {
            throw ApiException.unprocessable(ErrorCode.OUTSIDE_WORKING_HOURS, "Fora do expediente do profissional");
        }
        if (!schedule.timeOffOverlapping(professionalId, start, end).isEmpty()) {
            throw ApiException.unprocessable(ErrorCode.OUTSIDE_WORKING_HOURS, "O profissional está de folga nesse horário");
        }
    }

    public boolean fitsWorkingHours(UUID professionalId, LocalDate date, Instant start, Instant end) {
        return schedule.windowsFor(professionalId, date).stream()
                .anyMatch(w -> !start.isBefore(w.startOn(date)) && !end.isAfter(w.endOn(date)));
    }
}
