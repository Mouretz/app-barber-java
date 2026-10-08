package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

/**
 * Código do aparelho (X-Client-Code). Contrato (commit 9015a3d): ausente, fora do formato,
 * liberado ou desconhecido onde precisa existir dão o mesmo 401. No agendar, código novo bem
 * formado é aceito e fica preso ao telefone; em Meus horários e no cancelar ele precisa existir.
 */
class ClientDeviceIT extends DomainTest {

    private Res myBookings(String code) {
        return send(req(HttpMethod.GET, "/me/bookings").clientCode(code));
    }

    private Res cancel(String code, UUID bookingId) {
        return send(req(HttpMethod.POST, "/me/bookings/" + bookingId + "/cancel").clientCode(code).newKey());
    }

    private Res release(String token, UUID shop, UUID profileId) {
        return send(req(HttpMethod.POST, "/barbershops/" + shop + "/clients/" + profileId + "/release-device").token(token));
    }

    private UUID profileOf(UUID shop, String phone) {
        return db.sql("""
                        SELECT p.id FROM client_profiles p JOIN clients c ON c.id = p.client_id
                         WHERE p.barbershop_id = :b AND c.phone = :ph
                        """).param("b", shop).param("ph", phone).query(UUID.class).single();
    }

    @Test
    @DisplayName("Decisão do PO: GET /me/bookings com código bem formado que o servidor não conhece dá 401, nunca 200 vazio")
    void unknownWellFormedCodeOnList() {
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode()); // existe outro aparelho registrado
        Res unknown = myBookings(newCode());
        assertThat(unknown.status()).isEqualTo(401);
        assertThat(unknown.code()).isEqualTo("UNAUTHORIZED");
        assertThat(unknown.body()).isEqualTo(send(req(HttpMethod.GET, "/me/bookings")).body());
        assertThat(send(req(HttpMethod.GET, "/me/bookings?scope=past").clientCode(newCode())).status()).isEqualTo(401);
    }

    @Test
    @DisplayName("Ausente, mal formado, desconhecido e liberado em Meus horários: o mesmo 401")
    void sameUnauthorizedOnReads() {
        String code = newCode();
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code);
        Res missing = send(req(HttpMethod.GET, "/me/bookings"));
        Res malformed = myBookings("12345");
        Res unknown = myBookings(newCode());
        release(w.tGA, w.shopA, profileOf(w.shopA, T1));
        Res released = myBookings(code);
        for (Res r : new Res[] {missing, malformed, unknown, released}) {
            assertThat(r.status()).as(r.toString()).isEqualTo(401);
            assertThat(r.body()).isEqualTo(missing.body());
        }
        assertThat(missing.code()).isEqualTo("UNAUTHORIZED");
    }

    @Test
    @DisplayName("Cancelar com código desconhecido ou mal formado: 401, nunca 404 nem 422; agendamento intacto")
    void unauthorizedOnCancel() {
        Res b = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        Res unknown = cancel(newCode(), b.id());
        Res malformed = cancel("xyz", b.id());
        Res unknownBooking = cancel(newCode(), UUID.randomUUID());
        assertThat(unknown.status()).isEqualTo(401);
        assertThat(malformed.body()).isEqualTo(unknown.body());
        assertThat(unknownBooking.body()).isEqualTo(unknown.body());
        assertThat(statusInDb(b.id())).isEqualTo("SCHEDULED");
    }

    @Test
    @DisplayName("CT-04-08 código de outro aparelho não vê nem cancela horário alheio (404)")
    void otherClientsBooking() {
        Res joao = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        String rafael = newCode();
        clientBook(w.shopA, w.corte, w.p2, "2026-10-08T10:00", T2, rafael);
        assertThat(myBookings(rafael).body()).hasSize(1);
        assertThat(cancel(rafael, joao.id()).status()).isEqualTo(404);
        assertThat(statusInDb(joao.id())).isEqualTo("SCHEDULED");
    }

    @Test
    @DisplayName("Código novo bem formado no agendar é aceito e passa a abrir Meus horários")
    void newCodeRegistersOnCreate() {
        String code = newCode();
        assertThat(myBookings(code).status()).isEqualTo(401);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, code).status()).isEqualTo(201);
        Res mine = myBookings(code);
        assertThat(mine.status()).isEqualTo(200);
        assertThat(mine.body()).hasSize(1);
    }

    @Test
    @DisplayName("Gerente libera: código antigo dá 401 no agendar e no ler; aparelho novo agenda, fica preso e vê os horários antigos")
    void releaseFlow() {
        String old = newCode();
        Res first = clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, old);
        assertThat(release(w.tGA, w.shopA, profileOf(w.shopA, T1)).status()).isEqualTo(204);
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, old).status()).isEqualTo(401);
        assertThat(myBookings(old).status()).isEqualTo(401);
        assertThat(cancel(old, first.id()).status()).isEqualTo(401);
        String fresh = newCode();
        assertThat(clientBook(w.shopA, w.corte, w.p1, "2026-10-08T11:00", T1, fresh).status()).isEqualTo(201);
        assertThat(myBookings(fresh).body()).hasSize(2);
        // liberado vale para todas as barbearias
        assertThat(clientBook(w.shopB, w.corteB, w.pb1, "2026-10-08T11:00", T1, old).status()).isEqualTo(401);
        assertThat(count("SELECT count(*) FROM client_device_releases")).isEqualTo(1);
    }

    @Test
    @DisplayName("Liberar: profissional não gerente 403; ficha de outra barbearia 404; ficha só de balcão 409 DEVICE_RELEASE_NOT_ALLOWED")
    void releaseGuards() {
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        UUID profileA = profileOf(w.shopA, T1);
        assertThat(release(w.tP1, w.shopA, profileA).code()).isEqualTo("FORBIDDEN");
        assertThat(release(w.tGB, w.shopB, profileA).status()).isEqualTo(404);
        // Rafael só tem horário de balcão na A
        staffBook(w.tGA, w.shopA, w.corte, w.p2, "2026-10-08T10:00", "COUNTER", "Rafael", T2);
        Res r = release(w.tGA, w.shopA, profileOf(w.shopA, T2));
        assertThat(r.status()).isEqualTo(409);
        assertThat(r.code()).isEqualTo("DEVICE_RELEASE_NOT_ALLOWED");
        // telefone com app na A mas só balcão na B: na B não libera
        staffBook(w.tGB, w.shopB, w.corteB, w.pb1, "2026-10-08T10:00", "COUNTER", "João", T1);
        assertThat(release(w.tGB, w.shopB, profileOf(w.shopB, T1)).code()).isEqualTo("DEVICE_RELEASE_NOT_ALLOWED");
        assertThat(count("SELECT count(*) FROM clients WHERE device_code_hash IS NOT NULL")).isEqualTo(1);
    }

    @Test
    @DisplayName("Ficha mostra hasDevice; some depois de liberar")
    void hasDevice() {
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        UUID profile = profileOf(w.shopA, T1);
        Res before = send(req(HttpMethod.GET, "/barbershops/" + w.shopA + "/clients/" + profile).token(w.tGA));
        assertThat(before.body().get("hasDevice").asBoolean()).isTrue();
        assertThat(before.body().get("phone").asText()).isEqualTo("+5511987654321");
        release(w.tGA, w.shopA, profile);
        Res after = send(req(HttpMethod.GET, "/barbershops/" + w.shopA + "/clients/" + profile).token(w.tGA));
        assertThat(after.body().get("hasDevice").asBoolean()).isFalse();
    }
}
