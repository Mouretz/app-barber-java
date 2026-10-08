package br.com.cortaaqui.clients;

import br.com.cortaaqui.common.Phones;
import com.fasterxml.jackson.annotation.JsonInclude;
import br.com.cortaaqui.common.SpTime;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Ficha do cliente por barbearia. Sempre filtrada pela barbearia. */
@Repository
public class ClientProfiles {

    static final String SELECT = """
            SELECT cp.id, cp.barbershop_id, cp.client_id, cp.name, cp.email, cp.created_at, c.phone,
                   (c.device_code_hash IS NOT NULL) AS has_device
              FROM client_profiles cp LEFT JOIN clients c ON c.id = cp.client_id
            """;

    private final JdbcClient db;

    public ClientProfiles(JdbcClient db) {
        this.db = db;
    }

    public record ProfileRow(UUID id, UUID barbershopId, UUID clientId, String name, String email, OffsetDateTime createdAt,
                             String phone, boolean hasDevice) {
        public ClientJson json() {
            return new ClientJson(id, name, Phones.display(phone), hasDevice, email, SpTime.sp(createdAt.toInstant()));
        }
    }

    /** Client do contrato. {@code phone} vai como null no cliente de balcão sem telefone. */
    public record ClientJson(UUID id, String name, @JsonInclude(JsonInclude.Include.ALWAYS) String phone, boolean hasDevice,
                             String email, OffsetDateTime createdAt) {
    }

    static ProfileRow map(ResultSet rs, int i) throws SQLException {
        return new ProfileRow(rs.getObject("id", UUID.class), rs.getObject("barbershop_id", UUID.class),
                rs.getObject("client_id", UUID.class), rs.getString("name"), rs.getString("email"),
                rs.getObject("created_at", OffsetDateTime.class), rs.getString("phone"), rs.getBoolean("has_device"));
    }

    public Optional<ProfileRow> find(UUID barbershopId, UUID profileId) {
        return db.sql(SELECT + " WHERE cp.barbershop_id = :b AND cp.id = :id")
                .param("b", barbershopId).param("id", profileId).query(ClientProfiles::map).optional();
    }

    public Optional<ProfileRow> findByClient(UUID barbershopId, UUID clientId) {
        return db.sql(SELECT + " WHERE cp.barbershop_id = :b AND cp.client_id = :c")
                .param("b", barbershopId).param("c", clientId).query(ClientProfiles::map).optional();
    }

    /** Acha ou cria a ficha desta barbearia para o cliente global. Não mexe na ficha que já existe. */
    public UUID ensure(UUID barbershopId, UUID clientId, String name, String email) {
        db.sql("""
                        INSERT INTO client_profiles (barbershop_id, client_id, name, email) VALUES (:b, :c, :n, :e)
                        ON CONFLICT (barbershop_id, client_id) DO NOTHING
                        """)
                .param("b", barbershopId).param("c", clientId).param("n", name).param("e", email).update();
        return findByClient(barbershopId, clientId).orElseThrow().id();
    }

    /** Ficha de balcão sem telefone: só desta barbearia, sem cadastro global. */
    public UUID createWalkIn(UUID barbershopId, String name) {
        return db.sql("INSERT INTO client_profiles (barbershop_id, client_id, name) VALUES (:b, NULL, :n) RETURNING id")
                .param("b", barbershopId).param("n", name).query(UUID.class).single();
    }

    /** Nome mais recente que o próprio cliente usou (quando agenda numa barbearia nova sem mandar nome). */
    public Optional<String> lastNameOf(UUID clientId) {
        return db.sql("SELECT name FROM client_profiles WHERE client_id = :c ORDER BY updated_at DESC LIMIT 1")
                .param("c", clientId).query(String.class).optional();
    }
}
