package br.com.cortaaqui.auth;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** Vínculo da pessoa logada com uma barbearia. */
public record MembershipView(UUID barbershopId, String barbershopName, boolean manager, UUID professionalId) {

    public List<String> roles() {
        List<String> roles = new ArrayList<>();
        if (manager) {
            roles.add("MANAGER");
        }
        if (professionalId != null) {
            roles.add("PROFESSIONAL");
        }
        return roles;
    }

    /** Pode mexer na agenda deste profissional? Gerente: qualquer um. Profissional: só a dele. */
    public boolean canActOn(UUID professionalIdOfResource) {
        return manager || (professionalId != null && professionalId.equals(professionalIdOfResource));
    }

    /**
     * Filtro "só os meus dados": null para o gerente (vê tudo), o id do profissional para quem
     * não é gerente. Para o caixa (Eng. Dados): profissional vê só a própria linha.
     */
    public UUID ownProfessionalScope() {
        return manager ? null : professionalId;
    }
}
