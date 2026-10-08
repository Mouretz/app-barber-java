package br.com.cortaaqui.auth;

import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.common.Tokens;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

    /** Hash de uma senha aleatória, para o login com e-mail inexistente gastar o mesmo tempo. */
    private final String dummyHash;

    private final JdbcClient db;
    private final PasswordEncoder encoder;
    private final Clock clock;
    private final Duration sessionTtl;

    public AuthService(JdbcClient db, PasswordEncoder encoder, Clock clock,
                       @Value("${cortaaqui.session-ttl:P7D}") Duration sessionTtl) {
        this.db = db;
        this.encoder = encoder;
        this.clock = clock;
        this.sessionTtl = sessionTtl;
        this.dummyHash = encoder.encode(Tokens.newToken());
    }

    public record Session(String accessToken, java.time.OffsetDateTime expiresAt, StaffUserView user) {
    }

    public record StaffUserView(UUID id, String name, String email, List<MembershipJson> memberships) {
    }

    public record MembershipJson(UUID barbershopId, String barbershopName, List<String> roles, UUID professionalId) {
    }

    private record UserRow(UUID id, String name, String email, String passwordHash) {
    }

    @Transactional
    public Session login(String email, String password) {
        String normalized = email == null ? "" : email.strip().toLowerCase(Locale.ROOT);
        Optional<UserRow> user = db.sql("SELECT id, name, email, password_hash FROM staff_users WHERE email = :e")
                .param("e", normalized)
                .query((rs, i) -> new UserRow(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), rs.getString(4)))
                .optional();
        String hash = user.map(UserRow::passwordHash).orElse(null);
        boolean ok = encoder.matches(password == null ? "" : password, hash != null ? hash : dummyHash) && hash != null;
        // Profissional desativado (sem nenhum vínculo que dê acesso) leva o mesmo 401 da senha errada.
        if (ok && !hasAccess(user.get().id())) {
            ok = false;
        }
        if (!ok) {
            // Mesma resposta para senha errada e e-mail inexistente (CT-00-09).
            throw new ApiException(HttpStatus.UNAUTHORIZED, ErrorCode.UNAUTHORIZED, "E-mail ou senha inválidos");
        }
        UserRow u = user.get();
        String token = createSession(u.id());
        Instant expires = clock.instant().plus(sessionTtl);
        return new Session(token, SpTime.sp(expires), me(u.id()));
    }

    /** Cria a sessão e devolve o token (só o hash vai pro banco). */
    @Transactional
    public String createSession(UUID userId) {
        String token = Tokens.newToken();
        Instant now = clock.instant();
        db.sql("INSERT INTO staff_sessions (token_hash, user_id, created_at, expires_at) VALUES (:h, :u, :c, :x)")
                .param("h", Tokens.sha256(token)).param("u", userId)
                .param("c", SpTime.db(now)).param("x", SpTime.db(now.plus(sessionTtl)))
                .update();
        return token;
    }

    public Optional<StaffPrincipal> resolve(String token) {
        if (token == null || token.isBlank() || token.length() > 200) {
            return Optional.empty();
        }
        String hash = Tokens.sha256(token);
        return db.sql("""
                        SELECT u.id, u.name, u.email
                          FROM staff_sessions s JOIN staff_users u ON u.id = s.user_id
                         WHERE s.token_hash = :h AND s.revoked_at IS NULL AND s.expires_at > :now
                           AND EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = u.id AND """ + Access.USABLE_MEMBERSHIP + ")")
                .param("h", hash).param("now", SpTime.db(clock.instant()))
                .query((rs, i) -> new StaffPrincipal(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), hash))
                .optional();
    }

    /** Tem pelo menos um vínculo que dá acesso à Casa (gerente, ou profissional ativo)? */
    public boolean hasAccess(UUID userId) {
        return db.sql("SELECT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = :u AND " + Access.USABLE_MEMBERSHIP + ")")
                .param("u", userId).query(Boolean.class).single();
    }

    @Transactional
    public void logout(StaffPrincipal principal) {
        db.sql("UPDATE staff_sessions SET revoked_at = :now WHERE token_hash = :h AND revoked_at IS NULL")
                .param("now", SpTime.db(clock.instant())).param("h", principal.tokenHash())
                .update();
    }

    public StaffUserView me(UUID userId) {
        UserRow u = db.sql("SELECT id, name, email, password_hash FROM staff_users WHERE id = :id")
                .param("id", userId)
                .query((rs, i) -> new UserRow(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), null))
                .optional().orElseThrow(ApiException::unauthorized);
        List<MembershipJson> memberships = db.sql("""
                        SELECT m.barbershop_id, b.name, m.is_manager, m.professional_id
                          FROM memberships m JOIN barbershops b ON b.id = m.barbershop_id
                         WHERE m.user_id = :u
                           AND """ + Access.USABLE_MEMBERSHIP + " ORDER BY b.name")
                .param("u", userId)
                .query((rs, i) -> {
                    MembershipView m = new MembershipView(rs.getObject(1, UUID.class), rs.getString(2), rs.getBoolean(3),
                            rs.getObject(4, UUID.class));
                    return new MembershipJson(m.barbershopId(), m.barbershopName(), m.roles(), m.professionalId());
                })
                .list();
        return new StaffUserView(u.id(), u.name(), u.email(), memberships);
    }
}
