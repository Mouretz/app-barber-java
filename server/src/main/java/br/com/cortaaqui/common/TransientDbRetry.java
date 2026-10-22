package br.com.cortaaqui.common;

import java.sql.SQLException;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Rede de segurança para deadlock (40P01) e falha de serialização (40001). Roda a transação
 * inteira de novo uma vez. Tem que ficar FORA do @Transactional (no controller): a primeira
 * tentativa já foi desfeita pelo banco, então repetir não duplica nada e a Idempotency-Key
 * continua valendo. Se falhar de novo, devolve 409 CONCURRENT_UPDATE ("Não deu pra concluir
 * agora. Tente de novo."), nunca 500 e nunca SLOT_TAKEN: o horário pode estar livre, quem
 * travou foi o banco. Conflito de verdade (23P01, trigger de bloqueio) não é transitório e passa
 * direto, virando SLOT_TAKEN no {@link GlobalExceptionHandler}.
 *
 * <p>Usado em criar agendamento (app e Casa), criar bloqueio, mudar status e cancelar.
 */
public final class TransientDbRetry {

    private static final Logger log = LoggerFactory.getLogger(TransientDbRetry.class);

    private TransientDbRetry() {
    }

    /** Repete uma vez; se falhar de novo, 409 CONCURRENT_UPDATE. */
    public static <T> T once(Supplier<T> call) {
        return once(call, ApiException::concurrentUpdate);
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
                log.warn("transação falhou de novo com {}; devolvendo 409", sqlState(second));
                throw onGiveUp.get();
            }
        }
    }

    public static boolean isTransient(Throwable e) {
        String state = sqlState(e);
        return "40P01".equals(state) || "40001".equals(state);
    }

    /**
     * Falha de concorrência (para o 409 CONCURRENT_UPDATE): as transitórias acima e a espera de
     * trava estourada (55P03), que não é repetida porque já esperou.
     */
    public static boolean isConcurrencyFailure(Throwable e) {
        return isTransient(e) || "55P03".equals(sqlState(e));
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
