package br.com.cortaaqui.team;

import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/barbershops/{barbershopId}/professionals")
public class TeamController {

    private final ProfessionalService professionals;
    private final ScheduleService schedule;

    public TeamController(ProfessionalService professionals, ScheduleService schedule) {
        this.professionals = professionals;
        this.schedule = schedule;
    }

    @GetMapping
    public List<ProfessionalService.ProfessionalJson> list(@PathVariable UUID barbershopId) {
        return professionals.list(barbershopId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ProfessionalService.ProfessionalJson create(@PathVariable UUID barbershopId,
                                                       @RequestBody ProfessionalService.ProfessionalRequest req) {
        return professionals.create(barbershopId, req);
    }

    @PatchMapping("/{professionalId}")
    public ProfessionalService.ProfessionalJson update(@PathVariable UUID barbershopId, @PathVariable UUID professionalId,
                                                       @RequestBody ProfessionalService.ProfessionalPatch req) {
        return professionals.update(barbershopId, professionalId, req);
    }

    @GetMapping("/{professionalId}/working-hours")
    public ScheduleService.WeeklyHours getHours(@PathVariable UUID barbershopId, @PathVariable UUID professionalId) {
        return schedule.getWeekly(barbershopId, professionalId);
    }

    @PutMapping("/{professionalId}/working-hours")
    public ScheduleService.WeeklyHours replaceHours(@PathVariable UUID barbershopId, @PathVariable UUID professionalId,
                                                    @RequestBody ScheduleService.WeeklyHours req) {
        return schedule.replaceWeekly(barbershopId, professionalId, req);
    }

    @GetMapping("/{professionalId}/time-off")
    public List<ScheduleService.TimeOff> listTimeOff(@PathVariable UUID barbershopId, @PathVariable UUID professionalId) {
        return schedule.listTimeOff(barbershopId, professionalId);
    }

    @PostMapping("/{professionalId}/time-off")
    @ResponseStatus(HttpStatus.CREATED)
    public ScheduleService.TimeOff createTimeOff(@PathVariable UUID barbershopId, @PathVariable UUID professionalId,
                                                 @RequestBody ScheduleService.TimeOffRequest req) {
        return schedule.createTimeOff(barbershopId, professionalId, req);
    }

    @DeleteMapping("/{professionalId}/time-off/{timeOffId}")
    public ResponseEntity<Void> deleteTimeOff(@PathVariable UUID barbershopId, @PathVariable UUID professionalId,
                                              @PathVariable UUID timeOffId) {
        schedule.deleteTimeOff(barbershopId, professionalId, timeOffId);
        return ResponseEntity.noContent().build();
    }
}
