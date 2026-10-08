package br.com.cortaaqui.booking;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.catalog.CatalogService;
import br.com.cortaaqui.catalog.ServiceRow;
import br.com.cortaaqui.clients.ClientDirectory;
import br.com.cortaaqui.clients.ClientProfiles;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.Money;
import br.com.cortaaqui.common.Phones;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.common.Tokens;
import br.com.cortaaqui.team.ProfessionalRow;
import br.com.cortaaqui.team.Professionals;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Agendamento: criação (app e Casa), cancelamento do cliente e mudança de status pela Casa.
 * <ul>
 *   <li>Encaixe duplo: barrado pela constraint EXCLUDE (vira 409 SLOT_TAKEN).</li>
 *   <li>Pedido repetido (mesma Idempotency-Key): devolve o resultado original, sem criar nem mudar nada.</li>
 *   <li>Status só anda pra frente, com UPDATE ... WHERE status = 'SCHEDULED'. Quem chega depois leva 409 STATUS_CHANGED.</li>
 *   <li>Limite de 2 futuros pelo app por cliente, somando barbearias, com a linha do cliente travada.</li>
 * </ul>
 */
@Service
public class BookingService {

    public static final int CLIENT_APP_LIMIT = 2;
    private static final Set<String> TARGETS = Set.of("COMPLETED", "NO_SHOW", "CANCELED");

    private final JdbcClient db;
    private final Clock clock;
    private final Access access;
    private final ClientDirectory directory;
    private final ClientProfiles profiles;
    private final CatalogService catalog;
    private final Professionals professionals;
    private final BookingRules rules;
    private final BookingQueries queries;

    public BookingService(JdbcClient db, Clock clock, Access access, ClientDirectory directory, ClientProfiles profiles,
                          CatalogService catalog, Professionals professionals, BookingRules rules, BookingQueries queries) {
        this.db = db;
        this.clock = clock;
        this.access = access;
        this.directory = directory;
        this.profiles = profiles;
        this.catalog = catalog;
        this.professionals = professionals;
        this.rules = rules;
        this.queries = queries;
    }

    public record ClientInfo(String name, String phone, String email) {
    }

    public record ClientBookingRequest(UUID serviceId, UUID professionalId, OffsetDateTime startAt, ClientInfo client) {
    }

    public record StaffBookingRequest(UUID serviceId, UUID professionalId, OffsetDateTime startAt, String source,
                                      UUID clientId, ClientInfo newClient, String note) {
    }

    /** {@code replay} = mesma Idempotency-Key de antes (HTTP 200 em vez de 201). */
    public record Result(BookingView booking, boolean replay) {
    }

    // ------------------------------------------------------------------ app do cliente

    @Transactional
    public Result createByClient(UUID barbershopId, UUID idempotencyKey, String clientCode, ClientBookingRequest req) {
        // Código ausente, mal formado ou liberado: 401, com a mesma resposta (não revela se o código existe).
        if (!ClientDirectory.validCodeFormat(clientCode) || directory.isReleased(clientCode)) {
            throw ApiException.unauthorized();
        }
        Checks.start().required("serviceId", req.serviceId()).required("professionalId", req.professionalId())
                .required("startAt", req.startAt()).required("client", req.client()).orThrow();
        Checks.start().text("client.name", req.client().name(), 2, 80, true)
                .required("client.phone", req.client().phone()).email("client.email", req.client().email()).orThrow();
        Instant start = req.startAt().toInstant();
        String typedPhone = Phones.normalize(req.client().phone());
        String fingerprint = Tokens.sha256(String.join("|", "CLIENT", barbershopId.toString(), req.serviceId().toString(),
                req.professionalId().toString(), start.toString(), Tokens.sha256(clientCode.toLowerCase()), typedPhone));
        Optional<BookingRow> previous = replayCreate(idempotencyKey, fingerprint);
        if (previous.isPresent()) {
            return new Result(previous.get().clientView(clock.instant()), true);
        }

        // Um aparelho = um telefone, e um telefone = um aparelho.
        Optional<UUID> byCode = directory.findByCode(clientCode);
        ClientDirectory.ClientRow client;
        if (byCode.isPresent()) {
            client = directory.lock(byCode.get());
            if (!typedPhone.equals(client.phone())) {
                throw new ApiException(HttpStatus.CONFLICT, ErrorCode.DEVICE_PHONE_MISMATCH,
                        "Este aparelho já está ligado a outro telefone. Fale com a barbearia.");
            }
        } else {
            client = directory.lock(directory.upsertByPhone(typedPhone));
            // Prende o telefone a este aparelho na mesma transação do agendamento: se a
            // marcação for recusada por qualquer motivo, nada fica preso.
            directory.bindDevice(client, clientCode);
        }
        // Outro pedido com a mesma chave pode ter terminado enquanto esperávamos a trava do cliente.
        previous = replayCreate(idempotencyKey, fingerprint);
        if (previous.isPresent()) {
            return new Result(previous.get().clientView(clock.instant()), true);
        }

        ServiceRow service = catalog.find(barbershopId, req.serviceId()).filter(ServiceRow::active).orElseThrow(ApiException::notFound);
        ProfessionalRow pro = professionals.findActiveForBooking(barbershopId, req.professionalId()).orElseThrow(ApiException::notFound);
        rules.check(BookingRules.Actor.CLIENT, pro.id(), start, service.durationMinutes());

        Integer future = db.sql("""
                        SELECT count(*) FROM bookings
                         WHERE client_id = :c AND source = 'CLIENT_APP' AND status = 'SCHEDULED' AND start_at > :now
                        """)
                .param("c", client.id()).param("now", SpTime.db(clock.instant())).query(Integer.class).single();
        if (future >= CLIENT_APP_LIMIT) {
            throw ApiException.unprocessable(ErrorCode.BOOKING_LIMIT_REACHED,
                    "Você já tem 2 horários marcados pelo app");
        }

        UUID profileId = profiles.ensure(barbershopId, client.id(), req.client().name().strip(), req.client().email());

        UUID id = insert(barbershopId, pro, service, profileId, client.id(), "CLIENT_APP", start, null, idempotencyKey,
                fingerprint, null);
        return new Result(queries.find(barbershopId, id).orElseThrow().clientView(clock.instant()), false);
    }

    // ------------------------------------------------------------------ Casa (agenda e balcão)

    @Transactional
    public Result createByStaff(UUID barbershopId, UUID idempotencyKey, StaffBookingRequest req) {
        MembershipView m = access.member(barbershopId);
        Checks.start().required("professionalId", req.professionalId()).orThrow();
        // Profissional só marca na própria agenda (403 antes de qualquer outra validação).
        access.requireSelfOrManager(m, req.professionalId());
        Checks c = Checks.start().required("serviceId", req.serviceId()).required("startAt", req.startAt())
                .isTrue("STAFF".equals(req.source()) || "COUNTER".equals(req.source()), "source", "use STAFF ou COUNTER")
                .text("note", req.note(), 0, 200, false)
                .isTrue((req.clientId() == null) != (req.newClient() == null), "clientId", "informe clientId ou newClient");
        if (req.newClient() != null) {
            c.text("newClient.name", req.newClient().name(), 2, 80, true).email("newClient.email", req.newClient().email());
            // Balcão: telefone opcional. Marcação pela agenda: telefone obrigatório.
            if (!"COUNTER".equals(req.source())) {
                c.required("newClient.phone", req.newClient().phone());
            }
        }
        c.orThrow();
        Instant start = req.startAt().toInstant();
        String fingerprint = Tokens.sha256(String.join("|", "STAFF", m.barbershopId().toString(),
                access.principal().userId().toString(), req.serviceId().toString(), req.professionalId().toString(),
                start.toString(), req.source(), String.valueOf(req.clientId()),
                req.newClient() == null ? "" : String.valueOf(req.newClient().name()) + "/" + req.newClient().phone()));
        Optional<BookingRow> previous = replayCreate(idempotencyKey, fingerprint);
        if (previous.isPresent()) {
            return new Result(previous.get().staffView(m), true);
        }

        ServiceRow service = catalog.find(barbershopId, req.serviceId()).filter(ServiceRow::active).orElseThrow(ApiException::notFound);
        ProfessionalRow pro = professionals.findActiveForBooking(barbershopId, req.professionalId()).orElseThrow(ApiException::notFound);
        rules.check(BookingRules.Actor.STAFF, pro.id(), start, service.durationMinutes());

        UUID profileId;
        UUID clientId;
        if (req.clientId() != null) {
            ClientProfiles.ProfileRow p = profiles.find(barbershopId, req.clientId()).orElseThrow(ApiException::notFound);
            profileId = p.id();
            clientId = p.clientId();
        } else if (req.newClient().phone() != null && !req.newClient().phone().isBlank()) {
            String phone = Phones.normalize(req.newClient().phone());
            clientId = directory.upsertByPhone(phone);
            profileId = profiles.ensure(barbershopId, clientId, req.newClient().name().strip(), req.newClient().email());
        } else {
            // Balcão sem telefone: só a ficha desta barbearia, sem cadastro global.
            clientId = null;
            profileId = profiles.createWalkIn(barbershopId, req.newClient().name().strip());
        }

        UUID id = insert(barbershopId, pro, service, profileId, clientId, req.source(), start, req.note(), idempotencyKey,
                fingerprint, access.principal().userId());
        return new Result(queries.find(barbershopId, id).orElseThrow().staffView(m), false);
    }

    /** Agendamento já criado com esta chave. Mesma chave com outro pedido = 422 IDEMPOTENCY_KEY_REUSED. */
    private Optional<BookingRow> replayCreate(UUID key, String fingerprint) {
        Optional<BookingRow> existing = queries.findByIdempotencyKey(key);
        if (existing.isPresent() && !existing.get().requestFingerprint().equals(fingerprint)) {
            throw ApiException.unprocessable(ErrorCode.IDEMPOTENCY_KEY_REUSED, "Essa Idempotency-Key já foi usada em outro pedido");
        }
        return existing;
    }

    private UUID insert(UUID barbershopId, ProfessionalRow pro, ServiceRow service, UUID profileId, UUID clientId, String source,
                        Instant start, String note, UUID key, String fingerprint, UUID createdBy) {
        Instant end = start.plus(Duration.ofMinutes(service.durationMinutes()));
        return db.sql("""
                        INSERT INTO bookings (barbershop_id, professional_id, service_id, client_profile_id, client_id, source,
                                              start_at, end_at, service_name, duration_minutes, price_cents, note,
                                              idempotency_key, request_fingerprint, created_by_user_id, created_at)
                        VALUES (:b, :p, :s, :cp, :c, :src, :start, :end, :sname, :dur, :price, :note, :key, :fp, :by, :now)
                        RETURNING id
                        """)
                .param("b", barbershopId).param("p", pro.id()).param("s", service.id()).param("cp", profileId)
                .param("c", clientId).param("src", source).param("start", SpTime.db(start)).param("end", SpTime.db(end))
                .param("sname", service.name()).param("dur", service.durationMinutes()).param("price", service.priceCents())
                .param("note", note).param("key", key).param("fp", fingerprint).param("by", createdBy)
                .param("now", SpTime.db(clock.instant()))
                .query(UUID.class).single();
    }

    // ------------------------------------------------------------------ status

    @Transactional
    public Result changeStatusByStaff(UUID barbershopId, UUID bookingId, UUID idempotencyKey, String status) {
        MembershipView m = access.member(barbershopId);
        BookingRow b = queries.find(barbershopId, bookingId).orElseThrow(ApiException::notFound);
        access.requireSelfOrManager(m, b.professionalId());
        if (status == null || !TARGETS.contains(status)) {
            throw ApiException.invalidField("status", "use COMPLETED, NO_SHOW ou CANCELED");
        }
        if (!claimStatusRequest(idempotencyKey, barbershopId, bookingId, status, "STAFF")) {
            return new Result(queries.find(barbershopId, bookingId).orElseThrow().staffView(m), true);
        }
        if (!"SCHEDULED".equals(b.status())) {
            throw statusChanged();
        }
        Instant now = clock.instant();
        if (!"CANCELED".equals(status) && now.isBefore(b.startAt())) {
            throw ApiException.unprocessable(ErrorCode.TOO_EARLY, "Só a partir do horário de início");
        }
        int updated;
        switch (status) {
            case "COMPLETED" -> {
                int pct = professionalPercentNow(barbershopId, b.professionalId());
                Money.Split split = Money.split(b.priceCents(), pct);
                updated = db.sql("""
                                UPDATE bookings SET status = 'COMPLETED', completed_at = :now,
                                       professional_percent = :pp, shop_percent = :sp,
                                       professional_cents = :pc, shop_cents = :sc
                                 WHERE barbershop_id = :b AND id = :id AND status = 'SCHEDULED'
                                """)
                        .param("now", SpTime.db(now)).param("pp", split.professionalPercent()).param("sp", split.shopPercent())
                        .param("pc", split.professionalCents()).param("sc", split.shopCents())
                        .param("b", barbershopId).param("id", bookingId).update();
            }
            case "NO_SHOW" -> updated = db.sql("""
                            UPDATE bookings SET status = 'NO_SHOW', no_show_at = :now
                             WHERE barbershop_id = :b AND id = :id AND status = 'SCHEDULED'
                            """)
                    .param("now", SpTime.db(now)).param("b", barbershopId).param("id", bookingId).update();
            default -> updated = cancel(barbershopId, bookingId, "STAFF", now);
        }
        if (updated == 0) {
            throw statusChanged();
        }
        return new Result(queries.find(barbershopId, bookingId).orElseThrow().staffView(m), false);
    }

    @Transactional
    public Result cancelByClient(String clientCode, UUID bookingId, UUID idempotencyKey) {
        UUID clientId = directory.requireByCode(clientCode);
        BookingRow b = queries.findById(bookingId).filter(r -> clientId.equals(r.clientId()))
                .orElseThrow(ApiException::notFound);
        if (!claimStatusRequest(idempotencyKey, b.barbershopId(), bookingId, "CANCELED", "CLIENT")) {
            return new Result(queries.findById(bookingId).orElseThrow().clientView(clock.instant()), true);
        }
        if (!"SCHEDULED".equals(b.status())) {
            throw statusChanged();
        }
        Instant now = clock.instant();
        if (!b.clientCanCancel(now)) {
            throw ApiException.unprocessable(ErrorCode.CANCEL_WINDOW_CLOSED,
                    "Cancelamento só até 2 horas antes; fale com a barbearia");
        }
        if (cancel(b.barbershopId(), bookingId, "CLIENT", now) == 0) {
            throw statusChanged();
        }
        return new Result(queries.findById(bookingId).orElseThrow().clientView(now), false);
    }

    private int cancel(UUID barbershopId, UUID bookingId, String by, Instant now) {
        return db.sql("""
                        UPDATE bookings SET status = 'CANCELED', canceled_by = :by, canceled_at = :now
                         WHERE barbershop_id = :b AND id = :id AND status = 'SCHEDULED'
                        """)
                .param("by", by).param("now", SpTime.db(now)).param("b", barbershopId).param("id", bookingId).update();
    }

    /**
     * Registra a chave do pedido de status. Devolve false se a mesma chave já foi usada para
     * este mesmo pedido (repetição: o chamador devolve o resultado atual). Chave usada em outro
     * pedido = 422 IDEMPOTENCY_KEY_REUSED. Com dois pedidos iguais ao mesmo tempo, o segundo
     * espera o primeiro terminar (índice único) e vira repetição.
     */
    private boolean claimStatusRequest(UUID key, UUID barbershopId, UUID bookingId, String status, String actor) {
        int inserted = db.sql("""
                        INSERT INTO booking_status_requests (idempotency_key, barbershop_id, booking_id, requested_status, actor)
                        VALUES (:k, :b, :id, :s, :a) ON CONFLICT (idempotency_key) DO NOTHING
                        """)
                .param("k", key).param("b", barbershopId).param("id", bookingId).param("s", status).param("a", actor)
                .update();
        if (inserted == 1) {
            return true;
        }
        boolean same = db.sql("""
                        SELECT EXISTS (SELECT 1 FROM booking_status_requests
                                        WHERE idempotency_key = :k AND booking_id = :id AND requested_status = :s AND actor = :a)
                        """)
                .param("k", key).param("id", bookingId).param("s", status).param("a", actor).query(Boolean.class).single();
        if (!same) {
            throw ApiException.unprocessable(ErrorCode.IDEMPOTENCY_KEY_REUSED, "Essa Idempotency-Key já foi usada em outro pedido");
        }
        return false;
    }

    private static ApiException statusChanged() {
        return ApiException.conflict(ErrorCode.STATUS_CHANGED, "O status desse horário já mudou");
    }

    /** % do profissional no momento da conclusão: a própria, ou o padrão da barbearia. */
    private int professionalPercentNow(UUID barbershopId, UUID professionalId) {
        return db.sql("""
                        SELECT coalesce(p.professional_percent, s.default_professional_percent)
                          FROM professionals p JOIN barbershops s ON s.id = p.barbershop_id
                         WHERE p.barbershop_id = :b AND p.id = :p
                        """)
                .param("b", barbershopId).param("p", professionalId).query(Integer.class).single();
    }
}
