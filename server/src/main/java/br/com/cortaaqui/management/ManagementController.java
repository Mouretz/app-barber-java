package br.com.cortaaqui.management;

import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Gerência: % (história 20) e caixa do mês (história 8). */
@RestController
@RequestMapping("/barbershops/{barbershopId}")
public class ManagementController {

    private final CommissionService commission;
    private final CashService cash;

    public ManagementController(CommissionService commission, CashService cash) {
        this.commission = commission;
        this.cash = cash;
    }

    @GetMapping("/commission")
    public CommissionService.Settings getCommission(@PathVariable UUID barbershopId) {
        return commission.get(barbershopId);
    }

    @PutMapping("/commission")
    public CommissionService.Settings replaceCommission(@PathVariable UUID barbershopId,
                                                        @RequestBody CommissionService.Settings req) {
        return commission.replace(barbershopId, req);
    }

    @GetMapping("/cash")
    public CashService.MonthlyCash monthlyCash(@PathVariable UUID barbershopId, @RequestParam(required = false) String month) {
        // month sem "required": quem não é da barbearia recebe 404 antes do 422 do mês.
        return cash.monthly(barbershopId, month);
    }

    @GetMapping("/cash/professionals/{professionalId}")
    public CashService.ProfessionalCash professionalCash(@PathVariable UUID barbershopId, @PathVariable UUID professionalId,
                                                         @RequestParam(required = false) String month) {
        return cash.professional(barbershopId, professionalId, month);
    }
}
