package br.com.cortaaqui.unit;

import static org.assertj.core.api.Assertions.assertThat;

import br.com.cortaaqui.common.Money;
import java.util.Random;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class MoneyTest {

    @ParameterizedTest(name = "{0} centavos a {1}% -> {2} / {3}")
    @DisplayName("CT-20-08 arredondamento por agendamento (HALF_UP no profissional, casa fica com o resto)")
    @CsvSource({
            "5, 50, 3, 2",
            "1, 50, 1, 0",
            "3333, 60, 2000, 1333",
            "3333, 50, 1667, 1666",
            "1001, 33, 330, 671",
            "4000, 0, 0, 4000",
            "4000, 100, 4000, 0",
    })
    void split(int price, int pct, int professional, int shop) {
        Money.Split s = Money.split(price, pct);
        assertThat(s.professionalCents()).isEqualTo(professional);
        assertThat(s.shopCents()).isEqualTo(shop);
        assertThat(s.professionalPercent() + s.shopPercent()).isEqualTo(100);
    }

    @Test
    @DisplayName("CT-20-08 R$ 33,33 a 50% dá 16,67 para o profissional e 16,66 para a casa (HALF_UP em centavos)")
    void doubleWouldBeWrong() {
        assertThat(Money.split(3333, 50).professionalCents()).isEqualTo(1667);
        assertThat(Money.split(3333, 50).shopCents()).isEqualTo(1666);
    }

    @Test
    @DisplayName("CT-08-05 gerador: casa + profissional = preço, por agendamento e na soma, centavo por centavo")
    void sumsAlwaysMatch() {
        Random random = new Random(20261007);
        long gross = 0;
        long shop = 0;
        long professionals = 0;
        for (int i = 0; i < 20_000; i++) {
            int price = random.nextInt(100_000);
            int pct = random.nextInt(101);
            Money.Split s = Money.split(price, pct);
            assertThat(s.professionalCents() + s.shopCents()).isEqualTo(price);
            assertThat(s.professionalCents()).isBetween(0, price);
            gross += price;
            shop += s.shopCents();
            professionals += s.professionalCents();
        }
        assertThat(shop + professionals).isEqualTo(gross);
    }
}
