package br.com.cortaaqui.agenda;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.booking.BookingQueries;
import br.com.cortaaqui.booking.BookingView;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.team.ProfessionalPublic;
import br.com.cortaaqui.team.ProfessionalRow;
import br.com.cortaaqui.team.Professionals;
import br.com.cortaaqui.team.ScheduleService;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;

/** Agenda do dia por profissional. Profissional que não é gerente: só a dele (pedir outro = 403). */
@Service
public class AgendaService {

    private final Access access;
    private final Professionals professionals;
    private final ScheduleService schedule;
    private final BookingQueries bookings;
    private final BlockService blocks;

    public AgendaService(Access access, Professionals professionals, ScheduleService schedule, BookingQueries bookings,
                         BlockService blocks) {
        this.access = access;
        this.professionals = professionals;
        this.schedule = schedule;
        this.bookings = bookings;
        this.blocks = blocks;
    }

    public record ProfessionalAgenda(ProfessionalPublic professional, List<ScheduleService.TimeRange> workingWindows,
                                     List<BookingView> bookings, List<BlockService.Block> blocks,
                                     List<ScheduleService.TimeOff> timeOff) {
    }

    public record Agenda(LocalDate date, List<ProfessionalAgenda> professionals) {
    }

    public Agenda get(UUID barbershopId, LocalDate date, UUID professionalId) {
        MembershipView m = access.member(barbershopId);
        List<ProfessionalRow> list;
        if (professionalId != null) {
            access.requireSelfOrManager(m, professionalId);
            list = List.of(professionals.find(barbershopId, professionalId).filter(ProfessionalRow::active)
                    .orElseThrow(ApiException::notFound));
        } else if (m.manager()) {
            list = professionals.listActive(barbershopId);
        } else {
            list = professionals.find(barbershopId, m.professionalId()).filter(ProfessionalRow::active).stream().toList();
        }
        Instant from = SpTime.startOfDay(date);
        Instant to = SpTime.startOfDay(date.plusDays(1));
        List<ProfessionalAgenda> out = list.stream().map(p -> new ProfessionalAgenda(
                new ProfessionalPublic(p.id(), p.name(), p.photoUrl()),
                schedule.windowsFor(p.id(), date).stream().map(w -> new ScheduleService.TimeRange(
                        String.format("%02d:%02d", (w.startMinute() / 60) % 24, w.startMinute() % 60),
                        String.format("%02d:%02d", (w.endMinute() / 60) % 24, w.endMinute() % 60))).toList(),
                bookings.forProfessional(barbershopId, p.id(), from, to).stream()
                        .filter(b -> !b.startAt().isBefore(from)).map(b -> b.staffView(m)).toList(),
                blocks.forProfessional(barbershopId, p.id(), from, to),
                schedule.timeOffRows(p.id(), from, to))).toList();
        return new Agenda(date, out);
    }
}
