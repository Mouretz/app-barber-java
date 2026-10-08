package br.com.cortaaqui.team;

import java.util.UUID;

public record ProfessionalRow(UUID id, UUID barbershopId, String name, String photoUrl, boolean active,
                              Integer professionalPercent) {
}
