package br.com.cortaaqui.booking;

import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** App Casa: marcar (agenda e balcão) e mudar status. */
@RestController
@RequestMapping("/barbershops/{barbershopId}/staff/bookings")
public class StaffBookingController {

    private final BookingService bookings;

    public StaffBookingController(BookingService bookings) {
        this.bookings = bookings;
    }

    public record StatusChangeRequest(String status) {
    }

    @PostMapping
    public ResponseEntity<BookingView> create(@PathVariable UUID barbershopId,
                                              @RequestHeader("Idempotency-Key") UUID idempotencyKey,
                                              @RequestBody BookingService.StaffBookingRequest req) {
        BookingService.Result r = ClientBookingController.Idempotent.retryOnSameKey(
                () -> bookings.createByStaff(barbershopId, idempotencyKey, req));
        return ResponseEntity.status(r.replay() ? HttpStatus.OK : HttpStatus.CREATED).body(r.booking());
    }

    @PostMapping("/{bookingId}/status")
    public BookingView changeStatus(@PathVariable UUID barbershopId, @PathVariable UUID bookingId,
                                    @RequestHeader("Idempotency-Key") UUID idempotencyKey,
                                    @RequestBody StatusChangeRequest req) {
        return bookings.changeStatusByStaff(barbershopId, bookingId, idempotencyKey, req.status()).booking();
    }
}
