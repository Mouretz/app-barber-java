package br.com.cortaaqui.clients;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.booking.BookingQueries;
import br.com.cortaaqui.booking.BookingView;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.Checks;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.Phones;
import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Clientes na Casa: cada barbearia só vê e busca as próprias fichas. Buscar por telefone
 * só com o token da Casa. A mesma pessoa (telefone) pode ter ficha em várias barbearias.
 */
@Service
public class ClientsService {

    private final JdbcClient db;
    private final Access access;
    private final ClientDirectory directory;
    private final ClientProfiles profiles;
    private final BookingQueries bookings;
    private final boolean releaseRequiresAppBooking;

    public ClientsService(JdbcClient db, Access access, ClientDirectory directory, ClientProfiles profiles,
                          BookingQueries bookings,
                          @Value("${cortaaqui.release-device.require-app-booking:true}") boolean releaseRequiresAppBooking) {
        this.db = db;
        this.access = access;
        this.directory = directory;
        this.profiles = profiles;
        this.bookings = bookings;
        this.releaseRequiresAppBooking = releaseRequiresAppBooking;
    }

    public record ClientRequest(String name, String phone, String email) {
    }

    public record ClientPatch(String name, String phone, String email) {
    }

    public record ClientDetail(UUID id, String name, @JsonInclude(JsonInclude.Include.ALWAYS) String phone, boolean hasDevice,
                               String email, OffsetDateTime createdAt, List<BookingView> recentBookings) {
    }

    public List<ClientProfiles.ClientJson> search(UUID barbershopId, String q, Integer limit) {
        access.member(barbershopId);
        int lim = limit == null ? 20 : limit;
        Checks.start().range("limit", lim, 1, 50).text("q", q, 0, 80, false).orThrow();
        String text = q == null ? "" : q.strip();
        String digits = text.replaceAll("[^0-9]", "");
        boolean byPhone = digits.length() >= 4;
        return db.sql(ClientProfiles.SELECT + """
                         WHERE cp.barbershop_id = :b
                           AND (:q = ''
                                OR unaccent(lower(cp.name)) LIKE '%' || unaccent(lower(:q)) || '%'
                                OR (:byPhone AND c.phone LIKE '%' || :digits || '%'))
                         ORDER BY cp.name, cp.id
                         LIMIT :lim
                        """)
                .param("b", barbershopId).param("q", text).param("byPhone", byPhone).param("digits", digits)
                .param("lim", lim)
                .query(ClientProfiles::map).list().stream().map(ClientProfiles.ProfileRow::json).toList();
    }

    @Transactional
    public ClientProfiles.ClientJson create(UUID barbershopId, ClientRequest req) {
        access.member(barbershopId);
        Checks.start()
                .text("name", req.name(), 2, 80, true)
                .required("phone", req.phone())
                .email("email", req.email())
                .orThrow();
        String phone = Phones.normalize(req.phone());
        UUID clientId = directory.upsertByPhone(phone);
        if (profiles.findByClient(barbershopId, clientId).isPresent()) {
            throw ApiException.conflict(ErrorCode.PHONE_IN_USE, "Já existe cliente com esse telefone nesta barbearia");
        }
        // Se outro pedido criar a mesma ficha ao mesmo tempo, a UNIQUE (barbershop_id, client_id) vira 409 PHONE_IN_USE.
        UUID id = db.sql("INSERT INTO client_profiles (barbershop_id, client_id, name, email) VALUES (:b, :c, :n, :e) RETURNING id")
                .param("b", barbershopId).param("c", clientId).param("n", req.name().strip()).param("e", req.email())
                .query(UUID.class).single();
        return profiles.find(barbershopId, id).orElseThrow().json();
    }

    public ClientDetail get(UUID barbershopId, UUID profileId) {
        MembershipView m = access.member(barbershopId);
        ClientProfiles.ProfileRow p = profiles.find(barbershopId, profileId).orElseThrow(ApiException::notFound);
        List<BookingView> recent = bookings.recentForProfile(barbershopId, profileId, m.ownProfessionalScope(), 10)
                .stream().map(r -> r.staffView(m)).toList();
        ClientProfiles.ClientJson j = p.json();
        return new ClientDetail(j.id(), j.name(), j.phone(), j.hasDevice(), j.email(), j.createdAt(), recent);
    }

    /**
     * Editar ficha é só do gerente (regra do PO, 08/10: "editar ficha de outro" fica com o
     * gerente). A ficha é da barbearia, não do profissional, então não existe "ficha minha":
     * o profissional que não é gerente busca, abre e cadastra, mas não edita (403).
     */
    @Transactional
    public ClientProfiles.ClientJson update(UUID barbershopId, UUID profileId, ClientPatch req) {
        access.manager(barbershopId);
        ClientProfiles.ProfileRow p = profiles.find(barbershopId, profileId).orElseThrow(ApiException::notFound);
        Checks.start()
                .isTrue(req.name() != null || req.phone() != null || req.email() != null, "body", "informe ao menos um campo")
                .text("name", req.name(), 2, 80, false)
                .email("email", req.email())
                .orThrow();
        UUID clientId = p.clientId();
        if (req.phone() != null) {
            String phone = Phones.normalize(req.phone());
            UUID newClientId = directory.upsertByPhone(phone);
            if (!newClientId.equals(clientId) && profiles.findByClient(barbershopId, newClientId).isPresent()) {
                throw ApiException.conflict(ErrorCode.PHONE_IN_USE, "Já existe cliente com esse telefone nesta barbearia");
            }
            clientId = newClientId;
        }
        // Só a ficha desta barbearia muda; a ficha da mesma pessoa em outra barbearia fica igual.
        db.sql("""
                        UPDATE client_profiles SET name = :n, email = :e, client_id = :c, updated_at = now()
                         WHERE barbershop_id = :b AND id = :id
                        """)
                .param("n", req.name() != null ? req.name().strip() : p.name())
                .param("e", req.email() != null ? req.email() : p.email())
                .param("c", clientId).param("b", barbershopId).param("id", profileId)
                .update();
        return profiles.find(barbershopId, profileId).orElseThrow().json();
    }

    /**
     * Libera o telefone do aparelho atual (só gerente). Vale para todas as barbearias (o vínculo
     * é do telefone). O código antigo para de funcionar na hora; os agendamentos continuam do
     * cliente e o próximo aparelho que agendar com esse telefone passa a vê-los.
     */
    @Transactional
    public void releaseDevice(UUID barbershopId, UUID profileId) {
        access.manager(barbershopId);
        ClientProfiles.ProfileRow p = profiles.find(barbershopId, profileId).orElseThrow(ApiException::notFound);
        guardReleaseAllowed(barbershopId, p.clientId());
        directory.releaseDevice(p.clientId(), barbershopId, access.principal().userId());
    }

    /**
     * Trava de segurança (regra do MVP aprovada pelo PO): o gerente só libera telefone que
     * tem pelo menos um agendamento feito pelo app nesta barbearia; senão 409
     * DEVICE_RELEASE_NOT_ALLOWED. Fica num lugar só; a chave
     * cortaaqui.release-device.require-app-booking existe só para o caso de o PO mudar a regra.
     */
    private void guardReleaseAllowed(UUID barbershopId, UUID clientId) {
        if (clientId == null) {
            throw ApiException.conflict(ErrorCode.DEVICE_RELEASE_NOT_ALLOWED, "Ficha de balcão sem telefone não tem aparelho");
        }
        if (!releaseRequiresAppBooking) {
            return;
        }
        Boolean hasAppBooking = db.sql("""
                        SELECT EXISTS (SELECT 1 FROM bookings
                                        WHERE barbershop_id = :b AND client_id = :c AND source = 'CLIENT_APP')
                        """)
                .param("b", barbershopId).param("c", clientId).query(Boolean.class).single();
        if (!hasAppBooking) {
            throw ApiException.conflict(ErrorCode.DEVICE_RELEASE_NOT_ALLOWED,
                    "Esse cliente nunca agendou pelo app nesta barbearia");
        }
    }
}
