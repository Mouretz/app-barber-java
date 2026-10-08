package br.com.cortaaqui.config;

import br.com.cortaaqui.common.SpTime;
import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Relógio injetável (QA, item 6.1): nada de LocalDateTime.now() solto. Os testes trocam por um relógio fixo. */
@Configuration
public class TimeConfig {

    @Bean
    public Clock clock() {
        return Clock.system(SpTime.ZONE);
    }
}
