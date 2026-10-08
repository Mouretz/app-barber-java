package br.com.cortaaqui.catalog;

import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/barbershops/{barbershopId}/services")
public class ServiceController {

    private final CatalogService catalog;

    public ServiceController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @GetMapping
    public List<ServiceRow.ServiceJson> list(@PathVariable UUID barbershopId) {
        return catalog.list(barbershopId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ServiceRow.ServiceJson create(@PathVariable UUID barbershopId, @RequestBody CatalogService.ServiceRequest req) {
        return catalog.create(barbershopId, req);
    }

    @PatchMapping("/{serviceId}")
    public ServiceRow.ServiceJson update(@PathVariable UUID barbershopId, @PathVariable UUID serviceId,
                                         @RequestBody CatalogService.ServicePatch req) {
        return catalog.update(barbershopId, serviceId, req);
    }
}
