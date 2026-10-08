package br.com.cortaaqui.common;

import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Fila por agenda: quem cria agendamento ou bloqueio pega primeiro um advisory lock da agenda
 * do profissional (barbearia + profissional), que só solta no fim da transação.
 *
 * <p>Por quê: o EXCLUDE de agenda_occupancy grava a linha e só depois procura conflito. Dois
 * INSERTs sobrepostos ao mesmo tempo podiam gravar juntos e um esperar o outro: deadlock (40P01)
 * e 500 (CT-03-07). Com a fila, o segundo só grava depois que o primeiro terminou, vê a linha
 * já confirmada e leva o 23P01 normal (409 SLOT_TAKEN). A trava do banco continua sendo o EXCLUDE;
 * a fila só tira a corrida.
 *
 * <p>Ordem das travas: esta vem antes de qualquer outra da transação (cliente, aparelho), e
 * cada transação pega uma agenda só. Assim não tem ciclo de espera.
 */
@Component
public class AgendaLock {

    private final JdbcClient db;

    public AgendaLock(JdbcClient db) {
        this.db = db;
    }

    public void lock(UUID barbershopId, UUID professionalId) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            // Fora de transação o lock soltaria na hora (autocommit) e não serviria de nada.
            throw new IllegalStateException("AgendaLock precisa de transação ativa");
        }
        db.sql("SELECT pg_advisory_xact_lock(hashtextextended(:k, 0))")
                .param("k", "agenda:" + barbershopId + ":" + professionalId)
                .query((rs, i) -> 1).single();
    }
}
