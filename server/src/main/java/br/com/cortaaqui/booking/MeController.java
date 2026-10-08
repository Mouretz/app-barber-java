package br.com.cortaaqui.booking;

import br.com.cortaaqui.clients.ClientDirectory;
import br.com.cortaaqui.common.Checks;
import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Meus horários: só com o código do aparelho. Só o telefone não basta (CT-04-08). */
@RestController
@RequestMapping("/me/bookings")
public class MeController {

    private final ClientDirectory directory;
    private final BookingQueries queries;
    private final BookingService bookings;
    private final Clock clock;

    public MeController(ClientDirectory directory, BookingQueries queries, BookingService bookings, Clock clock) {
        this.directory = directory;
        this.queries = queries;
        this.bookings = bookings;
        this.clock = clock;
    }

    @GetMapping
    public List<BookingView> list(@RequestHeader(value = "X-Client-Code", required = false) String clientCode,
                                  @RequestParam(defaultValue = "upcoming") String scope,
                                  @RequestParam(defaultValue = "20") Integer limit) {
        UUID clientId = directory.requireByCode(clientCode);
        Checks.start().isTrue("upcoming".equals(scope) || "past".equals(scope), "scope", "use upcoming ou past")
                .range("limit", limit, 1, 50).orThrow();
        var now = clock.instant();
        return queries.forClient(clientId, "upcoming".equals(scope), now, limit).stream().map(b -> b.clientView(now)).toList();
    }

    @PostMapping("/{bookingId}/cancel")
    public BookingView cancel(@RequestHeader(value = "X-Client-Code", required = false) String clientCode,
                              @PathVariable UUID bookingId,
                              @RequestHeader("Idempotency-Key") UUID idempotencyKey) {
        return bookings.cancelByClient(clientCode, bookingId, idempotencyKey).booking();
    }
}
