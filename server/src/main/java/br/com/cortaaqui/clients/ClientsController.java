package br.com.cortaaqui.clients;

import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/barbershops/{barbershopId}/clients")
public class ClientsController {

    private final ClientsService clients;

    public ClientsController(ClientsService clients) {
        this.clients = clients;
    }

    @GetMapping
    public List<ClientProfiles.ClientJson> search(@PathVariable UUID barbershopId, @RequestParam(required = false) String q,
                                                  @RequestParam(required = false) Integer limit) {
        return clients.search(barbershopId, q, limit);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ClientProfiles.ClientJson create(@PathVariable UUID barbershopId, @RequestBody ClientsService.ClientRequest req) {
        return clients.create(barbershopId, req);
    }

    @GetMapping("/{clientId}")
    public ClientsService.ClientDetail get(@PathVariable UUID barbershopId, @PathVariable UUID clientId) {
        return clients.get(barbershopId, clientId);
    }

    @PatchMapping("/{clientId}")
    public ClientProfiles.ClientJson update(@PathVariable UUID barbershopId, @PathVariable UUID clientId,
                                            @RequestBody ClientsService.ClientPatch req) {
        return clients.update(barbershopId, clientId, req);
    }

    @PostMapping("/{clientId}/release-device")
    public ResponseEntity<Void> releaseDevice(@PathVariable UUID barbershopId, @PathVariable UUID clientId) {
        clients.releaseDevice(barbershopId, clientId);
        return ResponseEntity.noContent().build();
    }
}
