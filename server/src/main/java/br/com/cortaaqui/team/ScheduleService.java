package br.com.cortaaqui.team;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.SpTime;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.format.TextStyle;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Expediente semanal (versionado: a troca vale a partir de hoje e não mexe em agendamento)
 * e folgas. Escrever é só do gerente; ler, o gerente lê de todos e o profissional só o dele.
 */
@Service
public class ScheduleService {

    private static final Pattern HHMM = Pattern.compile("^([01]\\d|2[0-3]):[0-5]\\d$");
    /** Limites do expediente no MVP (regra do PO, 08/10): 08:00 a 21:00. */
    public static final int DAY_OPEN_MINUTE = 8 * 60;
    public static final int DAY_CLOSE_MINUTE = 21 * 60;
    private static final List<String> WEEKDAYS = List.of("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN");

    private final JdbcClient db;
    private final Access access;
    private final Professionals professionals;
    private final Clock clock;

    public ScheduleService(JdbcClient db, Access access, Professionals professionals, Clock clock) {
        this.db = db;
        this.access = access;
        this.professionals = professionals;
        this.clock = clock;
    }

    /**
     * Janela do expediente em minutos desde 00:00. A API só aceita 08:00 a 21:00; a leitura ainda
     * entende {@code endMinute} 1440 (00:00 do fim do dia) de linha antiga ou inserida direto no banco.
     */
    public record Window(int startMinute, int endMinute) {
        public static Window of(String start, String end) {
            return new Window(toMinutes(start, false), toMinutes(end, true));
        }

        public Instant startOn(LocalDate date) {
            return date.atStartOfDay(SpTime.ZONE).plusMinutes(startMinute).toInstant();
        }

        public Instant endOn(LocalDate date) {
            return date.atStartOfDay(SpTime.ZONE).plusMinutes(endMinute).toInstant();
        }
    }

    public record TimeRange(String start, String end) {
        static TimeRange of(Window w) {
            return new TimeRange(fmt(w.startMinute()), fmt(w.endMinute()));
        }
    }

    static int toMinutes(String hhmm, boolean isEnd) {
        LocalTime t = LocalTime.parse(hhmm);
        int m = t.getHour() * 60 + t.getMinute();
        return (isEnd && m == 0) ? 1440 : m;
    }

    static String fmt(int minutes) {
        int m = minutes % 1440;
        return String.format("%02d:%02d", m / 60, m % 60);
    }

    public record DayHours(String weekday, List<TimeRange> windows) {
    }

    public record WeeklyHours(List<DayHours> days) {
    }

    public record TimeOffRequest(OffsetDateTime startAt, OffsetDateTime endAt, String reason) {
    }

    public record TimeOff(UUID id, OffsetDateTime startAt, OffsetDateTime endAt, String reason) {
    }

    public record Interval(Instant start, Instant end) {
        public boolean overlaps(Instant s, Instant e) {
            return start.isBefore(e) && s.isBefore(end);
        }
    }

    // ------------------------------------------------------------------ leitura usada pela agenda e pelos livres

    /** Janelas do expediente que valem nesse dia (versão mais recente com valid_from <= dia). */
    public List<Window> windowsFor(UUID professionalId, LocalDate date) {
        return db.sql("""
                        SELECT w.start_minute, w.end_minute
                          FROM working_hours_windows w
                          JOIN working_hours_versions v ON v.id = w.version_id
                         WHERE v.professional_id = :p
                           AND v.valid_from = (SELECT max(valid_from) FROM working_hours_versions
                                                WHERE professional_id = :p AND valid_from <= :d)
                           AND w.weekday = :wd
                         ORDER BY w.start_minute
                        """)
                .param("p", professionalId).param("d", date).param("wd", date.getDayOfWeek().getValue())
                .query((rs, i) -> new Window(rs.getInt(1), rs.getInt(2)))
                .list();
    }

    public List<Interval> timeOffOverlapping(UUID professionalId, Instant from, Instant to) {
        return db.sql("SELECT start_at, end_at FROM time_off WHERE professional_id = :p AND start_at < :to AND end_at > :from")
                .param("p", professionalId).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query((rs, i) -> new Interval(rs.getObject(1, OffsetDateTime.class).toInstant(),
                        rs.getObject(2, OffsetDateTime.class).toInstant()))
                .list();
    }

    public List<TimeOff> timeOffRows(UUID professionalId, Instant from, Instant to) {
        return db.sql("""
                        SELECT id, start_at, end_at, reason FROM time_off
                         WHERE professional_id = :p AND start_at < :to AND end_at > :from ORDER BY start_at
                        """)
                .param("p", professionalId).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query((rs, i) -> new TimeOff(rs.getObject(1, UUID.class),
                        SpTime.sp(rs.getObject(2, OffsetDateTime.class).toInstant()),
                        SpTime.sp(rs.getObject(3, OffsetDateTime.class).toInstant()), rs.getString(4)))
                .list();
    }

    // ------------------------------------------------------------------ expediente

    public WeeklyHours getWeekly(UUID barbershopId, UUID professionalId) {
        MembershipView m = access.member(barbershopId);
        professionals.find(barbershopId, professionalId).orElseThrow(ApiException::notFound);
        access.requireSelfOrManager(m, professionalId);
        return weeklyAsOf(professionalId, SpTime.today(clock));
    }

    WeeklyHours weeklyAsOf(UUID professionalId, LocalDate date) {
        Map<Integer, List<TimeRange>> byDay = new TreeMap<>();
        db.sql("""
                        SELECT w.weekday, w.start_minute, w.end_minute
                          FROM working_hours_windows w
                          JOIN working_hours_versions v ON v.id = w.version_id
                         WHERE v.professional_id = :p
                           AND v.valid_from = (SELECT max(valid_from) FROM working_hours_versions
                                                WHERE professional_id = :p AND valid_from <= :d)
                         ORDER BY w.weekday, w.start_minute
                        """)
                .param("p", professionalId).param("d", date)
                .query((rs, i) -> {
                    byDay.computeIfAbsent(rs.getInt(1), k -> new ArrayList<>())
                            .add(TimeRange.of(new Window(rs.getInt(2), rs.getInt(3))));
                    return null;
                })
                .list();
        List<DayHours> days = new ArrayList<>();
        byDay.forEach((wd, windows) -> days.add(new DayHours(WEEKDAYS.get(wd - 1), windows)));
        return new WeeklyHours(days);
    }

    @Transactional
    public WeeklyHours replaceWeekly(UUID barbershopId, UUID professionalId, WeeklyHours req) {
        access.manager(barbershopId);
        professionals.findForUpdate(barbershopId, professionalId).orElseThrow(ApiException::notFound);
        Map<Integer, List<Window>> parsed = parseWeekly(req);
        LocalDate today = SpTime.today(clock);
        UUID versionId = db.sql("""
                        INSERT INTO working_hours_versions (barbershop_id, professional_id, valid_from)
                        VALUES (:b, :p, :d)
                        ON CONFLICT (professional_id, valid_from) DO UPDATE SET created_at = now()
                        RETURNING id
                        """)
                .param("b", barbershopId).param("p", professionalId).param("d", today)
                .query(UUID.class).single();
        db.sql("DELETE FROM working_hours_windows WHERE version_id = :v").param("v", versionId).update();
        parsed.forEach((wd, windows) -> windows.forEach(w -> db.sql("""
                        INSERT INTO working_hours_windows (barbershop_id, version_id, weekday, start_minute, end_minute)
                        VALUES (:b, :v, :wd, :s, :e)
                        """)
                .param("b", barbershopId).param("v", versionId).param("wd", wd).param("s", w.startMinute()).param("e", w.endMinute())
                .update()));
        return weeklyAsOf(professionalId, today);
    }

    /** Insere uma versão de expediente direto (seed e testes). */
    @Transactional
    public void setWeeklyFrom(UUID barbershopId, UUID professionalId, LocalDate validFrom, Map<DayOfWeek, List<Window>> days) {
        UUID versionId = db.sql("""
                        INSERT INTO working_hours_versions (barbershop_id, professional_id, valid_from)
                        VALUES (:b, :p, :d)
                        ON CONFLICT (professional_id, valid_from) DO UPDATE SET created_at = now()
                        RETURNING id
                        """)
                .param("b", barbershopId).param("p", professionalId).param("d", validFrom)
                .query(UUID.class).single();
        db.sql("DELETE FROM working_hours_windows WHERE version_id = :v").param("v", versionId).update();
        days.forEach((day, windows) -> windows.forEach(w -> db.sql("""
                        INSERT INTO working_hours_windows (barbershop_id, version_id, weekday, start_minute, end_minute)
                        VALUES (:b, :v, :wd, :s, :e)
                        """)
                .param("b", barbershopId).param("v", versionId).param("wd", day.getValue())
                .param("s", w.startMinute()).param("e", w.endMinute()).update()));
    }

    private Map<Integer, List<Window>> parseWeekly(WeeklyHours req) {
        Checks c = Checks.start();
        Map<Integer, List<Window>> out = new TreeMap<>();
        if (req == null || req.days() == null) {
            c.add("days", "obrigatório").orThrow();
        }
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < req.days().size(); i++) {
            DayHours d = req.days().get(i);
            String f = "days[" + i + "]";
            if (d == null || d.weekday() == null || !WEEKDAYS.contains(d.weekday())) {
                c.add(f + ".weekday", "dia inválido");
                continue;
            }
            if (!seen.add(d.weekday())) {
                c.add(f + ".weekday", "dia repetido");
                continue;
            }
            if (d.windows() == null || d.windows().isEmpty() || d.windows().size() > 3) {
                c.add(f + ".windows", "de 1 a 3 janelas por dia");
                continue;
            }
            List<Window> windows = new ArrayList<>();
            for (int j = 0; j < d.windows().size(); j++) {
                TimeRange r = d.windows().get(j);
                String wf = f + ".windows[" + j + "]";
                if (r == null || r.start() == null || r.end() == null || !HHMM.matcher(r.start()).matches()
                        || !HHMM.matcher(r.end()).matches()) {
                    c.add(wf, "hora inválida (HH:mm)");
                    continue;
                }
                Window w = Window.of(r.start(), r.end());
                boolean ok = checkEdge(c, wf + ".start", w.startMinute());
                ok &= checkEdge(c, wf + ".end", w.endMinute());
                if (!ok) {
                    continue;
                }
                if (w.endMinute() <= w.startMinute()) {
                    c.add(wf, "o fim tem que ser depois do início");
                    continue;
                }
                windows.add(w);
            }
            windows.sort(Comparator.comparingInt(Window::startMinute));
            for (int j = 1; j < windows.size(); j++) {
                if (windows.get(j).startMinute() < windows.get(j - 1).endMinute()) {
                    c.add(f + ".windows", "janelas sobrepostas");
                }
            }
            out.put(WEEKDAYS.indexOf(d.weekday()) + 1, windows);
        }
        c.orThrow();
        return out;
    }

    /**
     * Regra do PO (08/10): no MVP o expediente fica entre 08:00 e 21:00 e o início e o fim caem
     * na grade de 30 min (08:15 é recusado). 00:00 no fim (1440) fica fora, porque passa das 21:00.
     */
    private static boolean checkEdge(Checks c, String field, int minute) {
        if (minute < DAY_OPEN_MINUTE || minute > DAY_CLOSE_MINUTE) {
            c.add(field, "o expediente vai de 08:00 a 21:00");
            return false;
        }
        if (minute % SpTime.GRID_MINUTES != 0) {
            c.add(field, "use a grade de 30 min (:00 ou :30)");
            return false;
        }
        return true;
    }

    // ------------------------------------------------------------------ folgas

    public List<TimeOff> listTimeOff(UUID barbershopId, UUID professionalId) {
        MembershipView m = access.member(barbershopId);
        professionals.find(barbershopId, professionalId).orElseThrow(ApiException::notFound);
        access.requireSelfOrManager(m, professionalId);
        Instant from = SpTime.startOfDay(SpTime.today(clock));
        return timeOffRows(professionalId, from, Instant.parse("9999-12-31T00:00:00Z"));
    }

    @Transactional
    public TimeOff createTimeOff(UUID barbershopId, UUID professionalId, TimeOffRequest req) {
        access.manager(barbershopId);
        professionals.findForUpdate(barbershopId, professionalId).orElseThrow(ApiException::notFound);
        Checks.start()
                .required("startAt", req.startAt()).required("endAt", req.endAt())
                .text("reason", req.reason(), 0, 120, false)
                .orThrow();
        Instant s = req.startAt().toInstant();
        Instant e = req.endAt().toInstant();
        if (!e.isAfter(s)) {
            throw ApiException.invalidField("endAt", "o fim tem que ser depois do início");
        }
        Integer active = db.sql("""
                        SELECT count(*) FROM bookings
                         WHERE barbershop_id = :b AND professional_id = :p AND status = 'SCHEDULED'
                           AND start_at < :e AND end_at > :s
                        """)
                .param("b", barbershopId).param("p", professionalId).param("s", SpTime.db(s)).param("e", SpTime.db(e))
                .query(Integer.class).single();
        if (active > 0) {
            throw ApiException.conflict(ErrorCode.TIME_OFF_HAS_BOOKINGS, "Existe agendamento ativo no período; cancele antes");
        }
        return db.sql("""
                        INSERT INTO time_off (barbershop_id, professional_id, start_at, end_at, reason)
                        VALUES (:b, :p, :s, :e, :r) RETURNING id, start_at, end_at, reason
                        """)
                .param("b", barbershopId).param("p", professionalId).param("s", SpTime.db(s)).param("e", SpTime.db(e))
                .param("r", req.reason())
                .query((rs, i) -> new TimeOff(rs.getObject(1, UUID.class),
                        SpTime.sp(rs.getObject(2, OffsetDateTime.class).toInstant()),
                        SpTime.sp(rs.getObject(3, OffsetDateTime.class).toInstant()), rs.getString(4)))
                .single();
    }

    @Transactional
    public void deleteTimeOff(UUID barbershopId, UUID professionalId, UUID timeOffId) {
        access.manager(barbershopId);
        int n = db.sql("DELETE FROM time_off WHERE barbershop_id = :b AND professional_id = :p AND id = :id")
                .param("b", barbershopId).param("p", professionalId).param("id", timeOffId).update();
        if (n == 0) {
            throw ApiException.notFound();
        }
    }

    static String weekdayName(DayOfWeek d) {
        return d.getDisplayName(TextStyle.SHORT, Locale.ENGLISH).toUpperCase(Locale.ROOT);
    }
}
