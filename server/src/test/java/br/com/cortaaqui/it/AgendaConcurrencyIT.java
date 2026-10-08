package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

/**
 * CT-03-07 sob estresse. Pedidos simultâneos que se sobrepõem na agenda do mesmo profissional
 * não podem dar deadlock (40P01) nem 500: um entra (201) e os outros levam 409 SLOT_TAKEN.
 * Cada rodada usa uma janela de 1 hora diferente; o banco não é limpo entre rodadas.
 */
class AgendaConcurrencyIT extends DomainTest {

    static final int ROUNDS = 50;

    /** Resultado de um pedido; exceção que escapa do MockMvc conta como 500 (é o que o cliente veria). */
    record Out(String kind, int status, String code, String detail) {
        @Override
        public String toString() {
            return kind + " " + status + " " + code + (detail == null ? "" : " " + detail);
        }
    }

    private Callable<Out> safe(String kind, Callable<Res> call) {
        return () -> {
            try {
                Res r = call.call();
                return new Out(kind, r.status(), r.code(), r.status() >= 500 ? String.valueOf(r.body()) : null);
            } catch (Exception e) {
                return new Out(kind, 500, null, String.valueOf(e));
            }
        };
    }

    private Res staffBookNew(String startLocal, UUID service, String phone) {
        return send(req(HttpMethod.POST, "/barbershops/" + w.shopA + "/staff/bookings").token(w.tGA).newKey()
                .body(map("serviceId", service, "professionalId", w.p1, "startAt", sp(startLocal), "source", "STAFF",
                        "newClient", map("name", "Cliente Casa", "phone", phone))));
    }

    private Res createBlock(String startLocal, String endLocal) {
        return block(w.tGA, w.shopA, w.p1, startLocal, endLocal);
    }

    /** Início da janela da rodada r: dias 08/10..12/10, às 08:00..17:00 (cabe um Combo em HH:30). */
    private static LocalDateTime base(int r) {
        return LocalDateTime.of(2026, 10, 8 + r / 10, 8 + r % 10, 0);
    }

    /** Horário local da rodada r, deslocado em minutos, no formato que os atalhos usam. */
    private static String at(int r, int plusMinutes) {
        return base(r).plusMinutes(plusMinutes).toString();
    }

    private static String phone(int r, int i) {
        return "119%04d%04d".formatted(r, i);
    }

    private int bookingsInWindow(int r) {
        return db.sql("""
                        SELECT count(*) FROM bookings
                         WHERE professional_id = :p AND start_at >= :from::timestamptz AND start_at < :to::timestamptz
                        """)
                .param("p", w.p1).param("from", sp(at(r, 0))).param("to", sp(at(r, 60)))
                .query(Integer.class).single();
    }

    /**
     * Pedidos da rodada: todos se sobrepõem dois a dois (Combo 60 em HH:00, Corte 30 em HH:30,
     * Combo 60 em HH:30, Combo 60 em HH:00), alternando app do cliente e Casa.
     */
    private List<Callable<Out>> overlappingBookings(int r, int n) {
        List<Callable<Out>> tasks = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            UUID service = i == 1 ? w.corte : w.combo;
            String start = at(r, i == 1 || i == 2 ? 30 : 0);
            String ph = phone(r, i);
            if (i % 2 == 0) {
                tasks.add(safe("app", () -> clientBook(w.shopA, service, w.p1, start, ph, newCode())));
            } else {
                tasks.add(safe("casa", () -> staffBookNew(start, service, ph)));
            }
        }
        return tasks;
    }

    @Test
    @DisplayName("CT-03-07 estresse: 50 rodadas de 2 a 4 agendamentos simultâneos sobrepostos: 1 x 201, o resto 409 SLOT_TAKEN, nunca 500")
    void overlappingBookingsStress() {
        for (int r = 0; r < ROUNDS; r++) {
            int n = 2 + r % 3;
            List<Out> out = together(overlappingBookings(r, n));
            String round = "rodada " + r + ": " + out;
            assertThat(out).as(round).noneMatch(o -> o.status() >= 500);
            assertThat(out.stream().filter(o -> o.status() == 201)).as(round).hasSize(1);
            assertThat(out.stream().filter(o -> o.status() != 201))
                    .as(round).hasSize(n - 1)
                    .allSatisfy(o -> {
                        assertThat(o.status()).as(round).isEqualTo(409);
                        assertThat(o.code()).as(round).isEqualTo("SLOT_TAKEN");
                    });
            assertThat(bookingsInWindow(r)).as(round).isEqualTo(1);
        }
    }

    @Test
    @DisplayName("CT-03-07 estresse: 50 rodadas de bloqueios sobrepostos + agendamentos ao mesmo tempo: 1 bloqueio entra, agendamento no máximo 1, nunca 500")
    void blocksAndBookingsStress() {
        for (int r = 0; r < ROUNDS; r++) {
            int bookingsN = 1 + r % 2;
            List<Callable<Out>> tasks = new ArrayList<>();
            // Dois bloqueios que se sobrepõem (bloqueio x bloqueio: só um entra).
            int round0 = r;
            tasks.add(safe("bloqueio", () -> createBlock(at(round0, 0), at(round0, 60))));
            tasks.add(safe("bloqueio", () -> createBlock(at(round0, 30), at(round0, 90))));
            tasks.addAll(overlappingBookings(r, bookingsN));
            List<Out> out = together(tasks);
            String round = "rodada " + r + ": " + out;
            assertThat(out).as(round).noneMatch(o -> o.status() >= 500);
            List<Out> blocks = out.stream().filter(o -> o.kind().equals("bloqueio")).toList();
            List<Out> bookings = out.stream().filter(o -> !o.kind().equals("bloqueio")).toList();
            assertThat(blocks.stream().filter(o -> o.status() == 201)).as(round).hasSize(1);
            assertThat(blocks.stream().filter(o -> o.status() != 201)).as(round)
                    .allSatisfy(o -> assertThat(o.code()).as(round).isEqualTo("SLOT_TAKEN"));
            // Bloqueio x agendamento: quem chega antes vale. Bloqueio primeiro = agendamento 409;
            // agendamento primeiro = bloqueio entra por cima (overlapsBlock). Nunca 2 agendamentos.
            assertThat(bookings.stream().filter(o -> o.status() == 201).count()).as(round).isLessThanOrEqualTo(1);
            assertThat(bookings.stream().filter(o -> o.status() != 201)).as(round)
                    .allSatisfy(o -> {
                        assertThat(o.status()).as(round).isEqualTo(409);
                        assertThat(o.code()).as(round).isEqualTo("SLOT_TAKEN");
                    });
            assertThat(bookingsInWindow(r)).as(round).isLessThanOrEqualTo(1);
        }
    }
}
