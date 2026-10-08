package br.com.cortaaqui.unit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.ErrorCode;
import br.com.cortaaqui.common.Phones;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

class PhonesTest {

    @ParameterizedTest(name = "{0} -> {1}")
    @DisplayName("CT-17-11 normalização do telefone (máscara, com e sem 55, com +)")
    @CsvSource(delimiter = '|', value = {
            "(11) 98765-4321   | 5511987654321",
            "11987654321       | 5511987654321",
            "+55 11 98765-4321 | 5511987654321",
            "5511987654321     | 5511987654321",
            "(11) 3456-7890    | 551134567890",
            "551134567890      | 551134567890",
            "+55 (11) 3456-7890| 551134567890",
            "55987654321       | 5555987654321",
    })
    void normalizes(String raw, String expected) {
        assertThat(Phones.normalize(raw)).isEqualTo(expected);
        assertThat(Phones.display(Phones.normalize(raw))).isEqualTo("+" + expected);
    }

    @ParameterizedTest
    @DisplayName("CT-17-12 telefones inválidos: 9 dígitos, 12 dígitos sem 55, letras, DDI diferente de 55")
    @ValueSource(strings = {"987654321", "119876543210", "11 9876-ABCD", "+1 212 555 0100", "+351 912 345 678", "", "   ",
            "(11) 88765-4321", "+55", "0011987654321"})
    void rejectsInvalid(String raw) {
        assertThatThrownBy(() -> Phones.normalize(raw))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> {
                    ApiException a = (ApiException) e;
                    assertThat(a.code()).isEqualTo(ErrorCode.VALIDATION_ERROR);
                    assertThat(a.fields()).extracting("field").containsExactly("phone");
                });
    }

    @ParameterizedTest
    @DisplayName("Fixo com 10 dígitos e celular com 11 são números diferentes (sem acrescentar o 9)")
    @CsvSource({"(11) 8765-4321, 551187654321"})
    void landlineIsNotMobile(String raw, String expected) {
        assertThat(Phones.normalize(raw)).isEqualTo(expected).isNotEqualTo(Phones.normalize("(11) 98765-4321"));
    }
}
