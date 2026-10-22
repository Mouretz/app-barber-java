package br.com.cortaaqui.unit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.TransientDbRetry;
import java.sql.SQLException;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.http.HttpStatus;

class TransientDbRetryTest {

    private static RuntimeException db(String state) {
        return new PessimisticLockingFailureException("x", new SQLException("x", state));
    }

    @Test
    @DisplayName("Deadlock (40P01) uma vez: repete a transação e devolve o resultado")
    void retriesOnce() {
        AtomicInteger calls = new AtomicInteger();
        String r = TransientDbRetry.once(() -> {
            if (calls.incrementAndGet() == 1) {
                throw db("40P01");
            }
            return "ok";
        });
        assertThat(r).isEqualTo("ok");
        assertThat(calls).hasValue(2);
    }

    @Test
    @DisplayName("Deadlock ou serialização nas duas tentativas: 409 CONCURRENT_UPDATE (nunca SLOT_TAKEN), sem terceira tentativa")
    void givesUpWithConcurrentUpdate() {
        for (String state : new String[] {"40P01", "40001"}) {
            AtomicInteger calls = new AtomicInteger();
            assertThatThrownBy(() -> TransientDbRetry.once(() -> {
                calls.incrementAndGet();
                throw db(state);
            }))
                    .isInstanceOf(ApiException.class)
                    .satisfies(e -> {
                        ApiException api = (ApiException) e;
                        assertThat(api.code()).isEqualTo(ErrorCode.CONCURRENT_UPDATE);
                        assertThat(api.status()).isEqualTo(HttpStatus.CONFLICT);
                        assertThat(api.title()).isEqualTo("Não deu pra concluir agora. Tente de novo.");
                    });
            assertThat(calls).hasValue(2);
        }
    }

    @Test
    @DisplayName("Outros erros não são repetidos")
    void otherErrorsPassThrough() {
        AtomicInteger calls = new AtomicInteger();
        RuntimeException conflict = new DataIntegrityViolationException("x", new SQLException("x", "23P01"));
        assertThatThrownBy(() -> TransientDbRetry.once(() -> {
            calls.incrementAndGet();
            throw conflict;
        })).isSameAs(conflict);
        assertThat(calls).hasValue(1);
    }
}
