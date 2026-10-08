package br.com.cortaaqui.catalog;

import java.util.UUID;

public record ServiceRow(UUID id, UUID barbershopId, String name, int durationMinutes, int priceCents, boolean active) {

    public ServiceJson json() {
        return new ServiceJson(id, name, durationMinutes, priceCents, active);
    }

    public record ServiceJson(UUID id, String name, int durationMinutes, int priceCents, boolean active) {
    }
}
