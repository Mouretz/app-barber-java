package br.com.cortaaqui.agenda;

import java.time.LocalDate;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/barbershops/{barbershopId}")
public class AgendaController {

    private final AgendaService agenda;
    private final BlockService blocks;

    public AgendaController(AgendaService agenda, BlockService blocks) {
        this.agenda = agenda;
        this.blocks = blocks;
    }

    @GetMapping("/agenda")
    public AgendaService.Agenda agenda(@PathVariable UUID barbershopId, @RequestParam LocalDate date,
                                       @RequestParam(required = false) UUID professionalId) {
        return agenda.get(barbershopId, date, professionalId);
    }

    @PostMapping("/blocks")
    @ResponseStatus(HttpStatus.CREATED)
    public BlockService.Block createBlock(@PathVariable UUID barbershopId, @RequestBody BlockService.BlockRequest req) {
        return blocks.create(barbershopId, req);
    }

    @DeleteMapping("/blocks/{blockId}")
    public ResponseEntity<Void> deleteBlock(@PathVariable UUID barbershopId, @PathVariable UUID blockId) {
        blocks.delete(barbershopId, blockId);
        return ResponseEntity.noContent().build();
    }
}
