package br.com.cortaaqui.common;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;

/** Hora da barbearia: America/Sao_Paulo. "Dia" e "mês" sempre neste fuso, nunca no da JVM. */
public final class SpTime {

    public static final ZoneId ZONE = ZoneId.of("America/Sao_Paulo");
    /** Agenda abre 14 dias contando hoje: hoje até hoje + 13. */
    public static final int BOOKING_WINDOW_DAYS = 14;
    public static final int GRID_MINUTES = 30;

    private SpTime() {
    }

    public static LocalDate today(Clock clock) {
        return LocalDate.ofInstant(clock.instant(), ZONE);
    }

    public static OffsetDateTime sp(Instant instant) {
        return instant == null ? null : instant.atZone(ZONE).toOffsetDateTime();
    }

    /** Parâmetro para o JDBC (o driver do Postgres não aceita Instant direto). */
    public static OffsetDateTime db(Instant instant) {
        return instant == null ? null : instant.atOffset(ZoneOffset.UTC);
    }

    public static Instant startOfDay(LocalDate date) {
        return date.atStartOfDay(ZONE).toInstant();
    }

    public static boolean onGrid(Instant instant) {
        ZonedDateTime z = instant.atZone(ZONE);
        return z.getSecond() == 0 && z.getNano() == 0 && z.getMinute() % GRID_MINUTES == 0;
    }

    public static boolean insideBookingWindow(LocalDate date, Clock clock) {
        LocalDate today = today(clock);
        return !date.isBefore(today) && !date.isAfter(today.plusDays(BOOKING_WINDOW_DAYS - 1));
    }
}
