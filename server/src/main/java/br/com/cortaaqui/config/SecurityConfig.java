package br.com.cortaaqui.config;

import br.com.cortaaqui.auth.BearerTokenFilter;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.GlobalExceptionHandler;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AnonymousAuthenticationFilter;

/**
 * Rotas públicas: login, lista e página da barbearia, horários livres e o agendamento do
 * cliente (que se identifica pelo X-Client-Code, conferido no serviço). Todo o resto exige o
 * token da Casa. O papel (gerente/profissional) é por barbearia e é conferido no serviço
 * (ver {@link br.com.cortaaqui.auth.Access}), porque depende da barbearia da rota.
 */
@Configuration
public class SecurityConfig {

    private static final String P = WebConfig.API_PREFIX;

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, BearerTokenFilter bearerTokenFilter,
                                                   ObjectMapper objectMapper) throws Exception {
        http
                .csrf(c -> c.disable())
                .cors(Customizer.withDefaults())
                .httpBasic(b -> b.disable())
                .formLogin(f -> f.disable())
                .logout(l -> l.disable())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .addFilterBefore(bearerTokenFilter, AnonymousAuthenticationFilter.class)
                .authorizeHttpRequests(a -> a
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers(HttpMethod.POST, P + "/auth/login").permitAll()
                        .requestMatchers(HttpMethod.GET, P + "/barbershops", P + "/barbershops/*",
                                P + "/barbershops/*/availability").permitAll()
                        .requestMatchers(HttpMethod.POST, P + "/barbershops/*/bookings").permitAll()
                        .requestMatchers(P + "/me/**").permitAll()
                        .requestMatchers("/error").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(e -> e
                        .authenticationEntryPoint((req, res, ex) ->
                                GlobalExceptionHandler.write(res, objectMapper, ApiException.unauthorized()))
                        .accessDeniedHandler((req, res, ex) ->
                                GlobalExceptionHandler.write(res, objectMapper, ApiException.forbidden())));
        return http.build();
    }
}
