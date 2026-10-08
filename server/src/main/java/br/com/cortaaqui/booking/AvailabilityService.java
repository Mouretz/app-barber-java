package br.com.cortaaqui.booking;

import br.com.cortaaqui.catalog.CatalogService;
import br.com.cortaaqui.catalog.ServiceRow;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.team.ProfessionalRow;
import br.com.cortaaqui.team.Professionals;
import br.com.cortaaqui.team.ScheduleService;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/** Horários livres, calculados só no servidor (para o app do cliente). */
@Service
public class AvailabilityService {

    private final JdbcClient db;
    private final CatalogService catalog;
    private final Professionals professionals;
    private final ScheduleService schedule;
    private final BookingRules rules;
    private final Clock clock;

    public AvailabilityService(JdbcClient db, CatalogService catalog, Professionals professionals, ScheduleService schedule,
                               BookingRules rules, Clock clock) {
        this.db = db;
        this.catalog = catalog;
        this.professionals = professionals;
        this.schedule = schedule;
        this.rules = rules;
        this.clock = clock;
    }

    public record Slot(OffsetDateTime startAt, String period) {
    }

    public record Availability(LocalDate date, UUID professionalId, UUID serviceId, List<Slot> slots) {
    }

    public Availability forClient(UUID barbershopId, UUID serviceId, UUID professionalId, LocalDate date) {
        ServiceRow service = catalog.find(barbershopId, serviceId).filter(ServiceRow::active).orElseThrow(ApiException::notFound);
        ProfessionalRow pro = professionals.find(barbershopId, professionalId).filter(ProfessionalRow::active)
                .orElseThrow(ApiException::notFound);
        rules.requireDateInWindow(date, "date");
        return new Availability(date, pro.id(), service.id(),
                freeSlots(pro.id(), date, service.durationMinutes(), clock.instant().plus(BookingRules.CLIENT_MIN_NOTICE)));
    }

    /** Começos de 30 em 30 em que o serviço inteiro cabe numa janela, sem bater em ocupação ou folga. */
    List<Slot> freeSlots(UUID professionalId, LocalDate date, int durationMinutes, Instant earliestStart) {
        Duration duration = Duration.ofMinutes(durationMinutes);
        Instant dayStart = SpTime.startOfDay(date);
        Instant dayEnd = SpTime.startOfDay(date.plusDays(1));
        List<ScheduleService.Interval> busy = new ArrayList<>(occupied(professionalId, dayStart, dayEnd.plus(Duration.ofHours(8))));
        busy.addAll(schedule.timeOffOverlapping(professionalId, dayStart, dayEnd.plus(Duration.ofHours(8))));
        List<Slot> slots = new ArrayList<>();
        for (ScheduleService.Window w : schedule.windowsFor(professionalId, date)) {
            int firstMinute = ((w.startMinute() + SpTime.GRID_MINUTES - 1) / SpTime.GRID_MINUTES) * SpTime.GRID_MINUTES;
            Instant windowEnd = w.endOn(date);
            for (int m = firstMinute; m < w.endMinute(); m += SpTime.GRID_MINUTES) {
                Instant start = dayStart.plus(Duration.ofMinutes(m));
                Instant end = start.plus(duration);
                if (end.isAfter(windowEnd) || start.isBefore(earliestStart)) {
                    continue;
                }
                boolean clash = busy.stream().anyMatch(b -> b.overlaps(start, end));
                if (!clash) {
                    slots.add(new Slot(SpTime.sp(start), period(m)));
                }
            }
        }
        return slots;
    }

    /** Só filtro de tela, pelo início: manhã antes de 12:00, tarde até 17:59, noite depois. */
    static String period(int minuteOfDay) {
        if (minuteOfDay < 12 * 60) {
            return "MORNING";
        }
        return minuteOfDay < 18 * 60 ? "AFTERNOON" : "EVENING";
    }

    private List<ScheduleService.Interval> occupied(UUID professionalId, Instant from, Instant to) {
        return db.sql("""
                        SELECT lower(period), upper(period) FROM agenda_occupancy
                         WHERE professional_id = :p AND period && tstzrange(:from, :to, '[)')
                        """)
                .param("p", professionalId).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query((rs, i) -> new ScheduleService.Interval(rs.getObject(1, OffsetDateTime.class).toInstant(),
                        rs.getObject(2, OffsetDateTime.class).toInstant()))
                .list();
    }
}
