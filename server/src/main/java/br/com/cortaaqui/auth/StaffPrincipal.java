package br.com.cortaaqui.auth;

import java.util.UUID;

/** Pessoa logada na Casa (gerente e/ou profissional). Os papéis ficam por barbearia. */
public record StaffPrincipal(UUID userId, String name, String email, String tokenHash) {
}
