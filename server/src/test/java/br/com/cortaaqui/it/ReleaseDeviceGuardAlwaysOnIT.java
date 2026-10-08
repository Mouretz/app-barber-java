package br.com.cortaaqui.it;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.support.DomainTest;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.test.context.TestPropertySource;

/**
 * A trava DEVICE_RELEASE_NOT_ALLOWED é regra de produto e não pode ser desligada por
 * configuração. Aqui a chave antiga (cortaaqui.release-device.require-app-booking=false)
 * vem setada de propósito: o servidor tem que ignorá-la e continuar recusando com 409.
 * A config padrão (sem a chave) é coberta em {@link ClientDeviceIT#releaseGuards()}.
 */
@TestPropertySource(properties = "cortaaqui.release-device.require-app-booking=false")
class ReleaseDeviceGuardAlwaysOnIT extends DomainTest {

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
    @DisplayName("Chave antiga setada como false não desliga a trava: sem agendamento pelo app na barbearia dá 409")
    void oldKeyIsIgnored() {
        // Rafael só tem horário de balcão na A
        staffBook(w.tGA, w.shopA, w.corte, w.p2, "2026-10-08T10:00", "COUNTER", "Rafael", T2);
        Res r = release(w.tGA, w.shopA, profileOf(w.shopA, T2));
        assertThat(r.status()).isEqualTo(409);
        assertThat(r.code()).isEqualTo("DEVICE_RELEASE_NOT_ALLOWED");

        // João agendou pelo app na A, mas na B só tem balcão: na B continua 409
        clientBook(w.shopA, w.corte, w.p1, "2026-10-08T10:00", T1, newCode());
        staffBook(w.tGB, w.shopB, w.corteB, w.pb1, "2026-10-08T10:00", "COUNTER", "João", T1);
        Res b = release(w.tGB, w.shopB, profileOf(w.shopB, T1));
        assertThat(b.status()).isEqualTo(409);
        assertThat(b.code()).isEqualTo("DEVICE_RELEASE_NOT_ALLOWED");
        assertThat(count("SELECT count(*) FROM client_device_releases")).isZero();

        // Na A, onde ele agendou pelo app, o gerente libera normalmente
        assertThat(release(w.tGA, w.shopA, profileOf(w.shopA, T1)).status()).isEqualTo(204);
        assertThat(count("SELECT count(*) FROM client_device_releases")).isEqualTo(1);
    }
}
