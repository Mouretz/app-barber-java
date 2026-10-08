package br.com.cortaaqui.common;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Divisão casa/profissional, por agendamento, na conclusão.
 * profissional = preço × % / 100 arredondado ao centavo (meio centavo sobe, HALF_UP);
 * casa = preço − profissional. Sempre em centavos inteiros e BigDecimal, nunca double.
 */
public final class Money {

    private Money() {
    }

    public record Split(int professionalPercent, int shopPercent, int professionalCents, int shopCents) {
    }

    public static Split split(int priceCents, int professionalPercent) {
        if (priceCents < 0) {
            throw new IllegalArgumentException("preço negativo");
        }
        if (professionalPercent < 0 || professionalPercent > 100) {
            throw new IllegalArgumentException("% fora de 0..100");
        }
        int professionalCents = BigDecimal.valueOf(priceCents)
                .multiply(BigDecimal.valueOf(professionalPercent))
                .divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP)
                .intValueExact();
        return new Split(professionalPercent, 100 - professionalPercent, professionalCents, priceCents - professionalCents);
    }
}
