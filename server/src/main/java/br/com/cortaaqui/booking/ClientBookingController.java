package br.com.cortaaqui.booking;

import java.time.LocalDate;
import java.util.UUID;
import java.util.function.Supplier;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** App Cliente: horários livres e agendar. */
@RestController
@RequestMapping("/barbershops/{barbershopId}")
public class ClientBookingController {

    private final AvailabilityService availability;
    private final BookingService bookings;

    public ClientBookingController(AvailabilityService availability, BookingService bookings) {
        this.availability = availability;
        this.bookings = bookings;
    }

    @GetMapping("/availability")
    public AvailabilityService.Availability availability(@PathVariable UUID barbershopId, @RequestParam UUID serviceId,
                                                         @RequestParam UUID professionalId, @RequestParam LocalDate date) {
        return availability.forClient(barbershopId, serviceId, professionalId, date);
    }

    @PostMapping("/bookings")
    public ResponseEntity<BookingView> create(@PathVariable UUID barbershopId,
                                              @RequestHeader("Idempotency-Key") UUID idempotencyKey,
                                              @RequestHeader(value = "X-Client-Code", required = false) String clientCode,
                                              @RequestBody BookingService.ClientBookingRequest req) {
        BookingService.Result r = Idempotent.retryOnSameKey(() -> bookings.createByClient(barbershopId, idempotencyKey, clientCode, req));
        return ResponseEntity.status(r.replay() ? HttpStatus.OK : HttpStatus.CREATED).body(r.booking());
    }

    /** Dois pedidos com a mesma chave ao mesmo tempo: o segundo bate no índice único e repete como "mesma chave". */
    static final class Idempotent {
        static BookingService.Result retryOnSameKey(Supplier<BookingService.Result> call) {
            try {
                return call.get();
            } catch (DuplicateKeyException e) {
                if (String.valueOf(e.getMessage()).contains("uk_bookings_idempotency_key")) {
                    return call.get();
                }
                throw e;
            }
        }
    }
}
