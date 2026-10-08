package br.com.cortaaqui.common;

import java.sql.SQLException;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Rede de segurança para deadlock (40P01) e falha de serialização (40001). Roda a transação
 * inteira de novo uma vez. Tem que ficar FORA do @Transactional (no controller): a primeira
 * tentativa já foi desfeita pelo banco, então repetir não duplica nada e a Idempotency-Key
 * continua valendo. Se falhar de novo, devolve o erro de negócio que o chamador escolher
 * (para criar agendamento ou bloqueio, 409 SLOT_TAKEN), nunca 500.
 */
public final class TransientDbRetry {

    private static final Logger log = LoggerFactory.getLogger(TransientDbRetry.class);

    private TransientDbRetry() {
    }

    public static <T> T once(Supplier<T> call, Supplier<ApiException> onGiveUp) {
        try {
            return call.get();
        } catch (RuntimeException first) {
            if (!isTransient(first)) {
                throw first;
            }
            log.warn("transação repetida depois de {}", sqlState(first));
            try {
                return call.get();
            } catch (RuntimeException second) {
                if (!isTransient(second)) {
                    throw second;
                }
                log.warn("transação falhou de novo com {}; devolvendo erro de negócio", sqlState(second));
                throw onGiveUp.get();
            }
        }
    }

    public static boolean isTransient(Throwable e) {
        String state = sqlState(e);
        return "40P01".equals(state) || "40001".equals(state);
    }

    static String sqlState(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof SQLException s && s.getSQLState() != null) {
                return s.getSQLState();
            }
        }
        return null;
    }
}
