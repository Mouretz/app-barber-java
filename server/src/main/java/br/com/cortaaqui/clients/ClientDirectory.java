package br.com.cortaaqui.clients;

import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.Tokens;
import java.util.Optional;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Cliente global (um por telefone) e o vínculo com o aparelho.
 * O código do aparelho é gerado no celular no 1º agendamento e mandado em X-Client-Code;
 * o servidor guarda só o SHA-256 e nunca devolve o código.
 */
@Component
public class ClientDirectory {

    private final JdbcClient db;

    public ClientDirectory(JdbcClient db) {
        this.db = db;
    }

    public record ClientRow(UUID id, String phone, String deviceCodeHash) {
    }

    /** O contrato pede UUID (gerado pelo app). Guardamos o hash da forma canônica (minúscula). */
    public static boolean validCodeFormat(String code) {
        return canonical(code) != null;
    }

    static String canonical(String code) {
        if (code == null || code.length() != 36) {
            return null;
        }
        try {
            return UUID.fromString(code).toString();
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    static String hash(String code) {
        return Tokens.sha256(canonical(code));
    }

    /** Código liberado pelo gerente: não vale mais, nem para agendar. */
    public boolean isReleased(String code) {
        if (!validCodeFormat(code)) {
            return false;
        }
        return db.sql("SELECT EXISTS (SELECT 1 FROM client_device_releases WHERE code_hash = :h)")
                .param("h", hash(code)).query(Boolean.class).single();
    }

    /** Cliente dono deste código, ou vazio. */
    public Optional<UUID> findByCode(String code) {
        if (!validCodeFormat(code)) {
            return Optional.empty();
        }
        return db.sql("SELECT id FROM clients WHERE device_code_hash = :h")
                .param("h", hash(code)).query(UUID.class).optional();
    }

    /** Para as rotas /me: código ausente ou desconhecido = 401, sem dizer se o telefone existe. */
    public UUID requireByCode(String code) {
        return findByCode(code).orElseThrow(ApiException::unauthorized);
    }

    /** Acha ou cria o cliente pelo telefone já normalizado. Seguro com pedidos ao mesmo tempo. */
    public UUID upsertByPhone(String normalizedPhone) {
        db.sql("INSERT INTO clients (phone) VALUES (:p) ON CONFLICT (phone) DO NOTHING")
                .param("p", normalizedPhone).update();
        return db.sql("SELECT id FROM clients WHERE phone = :p").param("p", normalizedPhone).query(UUID.class).single();
    }

    /** Trava a linha do cliente até o fim da transação (limite de 2 somando barbearias). */
    public ClientRow lock(UUID clientId) {
        return db.sql("SELECT id, phone, device_code_hash FROM clients WHERE id = :id FOR UPDATE")
                .param("id", clientId)
                .query((rs, i) -> new ClientRow(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3)))
                .single();
    }

    /**
     * Prende o telefone a este aparelho no 1º agendamento. Se o telefone já está em outro
     * aparelho, recusa: o cliente fala com a barbearia, que pode liberar.
     */
    public void bindDevice(ClientRow client, String code) {
        String hash = hash(code);
        if (client.deviceCodeHash() == null) {
            db.sql("UPDATE clients SET device_code_hash = :h WHERE id = :id")
                    .param("h", hash).param("id", client.id()).update();
        } else if (!client.deviceCodeHash().equals(hash)) {
            throw new ApiException(HttpStatus.CONFLICT, ErrorCode.PHONE_ON_OTHER_DEVICE,
                    "Esse telefone já está em outro aparelho. Fale com a barbearia.");
        }
    }

    /** Solta o telefone do aparelho e guarda o hash do código antigo, que passa a dar 401. */
    public void releaseDevice(UUID clientId, UUID barbershopId, UUID userId) {
        db.sql("""
                        INSERT INTO client_device_releases (code_hash, client_id, barbershop_id, released_by_user_id)
                        SELECT device_code_hash, id, :b, :u FROM clients WHERE id = :id AND device_code_hash IS NOT NULL
                        ON CONFLICT (code_hash) DO NOTHING
                        """)
                .param("b", barbershopId).param("u", userId).param("id", clientId).update();
        db.sql("UPDATE clients SET device_code_hash = NULL WHERE id = :id").param("id", clientId).update();
    }
}
