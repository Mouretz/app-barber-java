package br.com.cortaaqui.support;

import br.com.cortaaqui.common.SpTime;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.concurrent.atomic.AtomicReference;

/** Relógio fixo dos testes (QA 9.7: nenhum teste depende da hora em que roda). */
public class MutableClock extends Clock {

    private final AtomicReference<Instant> now = new AtomicReference<>(Instant.parse("2026-10-07T12:00:00Z"));

    public void set(String isoWithOffset) {
        now.set(OffsetDateTime.parse(isoWithOffset).toInstant());
    }

    /** Hora de Brasília, ex.: "2026-10-07T09:30:00". */
    public void setSp(String localIso) {
        now.set(java.time.LocalDateTime.parse(localIso).atZone(SpTime.ZONE).toInstant());
    }

    @Override
    public ZoneId getZone() {
        return SpTime.ZONE;
    }

    @Override
    public Clock withZone(ZoneId zone) {
        return Clock.fixed(now.get(), zone);
    }

    @Override
    public Instant instant() {
        return now.get();
    }
}
