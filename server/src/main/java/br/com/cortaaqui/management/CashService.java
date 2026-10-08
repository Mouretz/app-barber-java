package br.com.cortaaqui.management;

import br.com.cortaaqui.auth.Access;
import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.booking.BookingQueries;
import br.com.cortaaqui.booking.BookingRow;
import br.com.cortaaqui.booking.BookingView;
import br.com.cortaaqui.common.ApiException;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.team.ProfessionalPublic;
import br.com.cortaaqui.team.ProfessionalRow;
import br.com.cortaaqui.team.Professionals;
import com.fasterxml.jackson.annotation.JsonUnwrapped;
import java.time.Instant;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/**
 * Caixa do mês (história 8).
 *
 * <p>Regras:
 * <ul>
 *   <li>Só agendamentos {@code COMPLETED}. Falta, cancelado e agendado ainda não concluído ficam de fora.
 *       Balcão entra normalmente.</li>
 *   <li>O mês é o do <b>início</b> do atendimento ({@code start_at}) no fuso America/Sao_Paulo,
 *       não o da conclusão nem o do relógio do servidor.</li>
 *   <li>Nada é recalculado: soma os centavos gravados em cada agendamento na conclusão
 *       ({@code price_cents}, {@code professional_cents}, {@code shop_cents}). Mudar a % depois
 *       não mexe no caixa antigo.</li>
 *   <li>Somas em {@code long}: inteiros do começo ao fim, nunca ponto flutuante.</li>
 *   <li>Papel: gerente vê tudo. Profissional que não é gerente vê só a própria linha, sem a parte
 *       da casa ({@code shopCents} fica de fora do JSON).</li>
 * </ul>
 */
@Service
public class CashService {

    private static final Pattern MONTH = Pattern.compile("^\\d{4}-(0[1-9]|1[0-2])$");

    private final JdbcClient db;
    private final Access access;
    private final Professionals professionals;
    private final BookingQueries bookings;

    public CashService(JdbcClient db, Access access, Professionals professionals, BookingQueries bookings) {
        this.db = db;
        this.access = access;
        this.professionals = professionals;
        this.bookings = bookings;
    }

    /** CashTotals do contrato. {@code shopCents} null = não vai no JSON (profissional que não é gerente). */
    public record Totals(long completedCount, long grossCents, Long shopCents, long professionalCents) {

        static final Totals ZERO = new Totals(0, 0, 0L, 0);

        Totals plus(Totals o) {
            return new Totals(completedCount + o.completedCount, grossCents + o.grossCents,
                    shopCents == null || o.shopCents == null ? null : shopCents + o.shopCents,
                    professionalCents + o.professionalCents);
        }

        Totals withoutShop() {
            return new Totals(completedCount, grossCents, null, professionalCents);
        }
    }

    /** Linha de {@code byProfessional}: professional + CashTotals no mesmo objeto (allOf no contrato). */
    public record ProfessionalLine(ProfessionalPublic professional, @JsonUnwrapped Totals totals) {
    }

    public record MonthlyCash(String month, Totals totals, List<ProfessionalLine> byProfessional) {
    }

    public record ProfessionalCash(String month, ProfessionalPublic professional, Totals totals, List<BookingView> bookings) {
    }

    /** "2026-10" -> YearMonth. Fora do formato AAAA-MM: 422 VALIDATION_ERROR no campo month. */
    public static YearMonth parseMonth(String month) {
        if (month == null || !MONTH.matcher(month).matches()) {
            throw ApiException.invalidField("month", "use AAAA-MM, ex.: 2026-10");
        }
        try {
            return YearMonth.parse(month);
        } catch (DateTimeParseException e) {
            throw ApiException.invalidField("month", "use AAAA-MM, ex.: 2026-10");
        }
    }

    /** Começo do mês em Brasília (00:00 do dia 1), como instante. */
    static Instant monthStart(YearMonth month) {
        return SpTime.startOfDay(month.atDay(1));
    }

    public MonthlyCash monthly(UUID barbershopId, String monthParam) {
        MembershipView m = access.member(barbershopId);
        YearMonth month = parseMonth(monthParam);
        UUID scope = m.ownProfessionalScope(); // null = gerente (vê todos)
        Instant from = monthStart(month);
        Instant to = monthStart(month.plusMonths(1));
        // Gerente: todos os ativos (mesmo zerados) + desativados que tiveram concluído no mês.
        // Profissional: só a linha dele, mesmo zerada.
        List<ProfessionalLine> lines = db.sql("""
                        SELECT p.id, p.name, p.photo_url,
                               count(b.id)                          AS completed_count,
                               coalesce(sum(b.price_cents), 0)        AS gross_cents,
                               coalesce(sum(b.shop_cents), 0)         AS shop_cents,
                               coalesce(sum(b.professional_cents), 0) AS professional_cents
                          FROM professionals p
                          LEFT JOIN bookings b
                                 ON b.barbershop_id = p.barbershop_id AND b.professional_id = p.id
                                AND b.status = 'COMPLETED' AND b.start_at >= :from AND b.start_at < :to
                         WHERE p.barbershop_id = :b
                           AND (CAST(:scope AS uuid) IS NULL OR p.id = :scope)
                         GROUP BY p.id
                        HAVING p.active OR count(b.id) > 0 OR CAST(:scope AS uuid) IS NOT NULL
                         ORDER BY p.name, p.id
                        """)
                .param("b", barbershopId).param("scope", scope).param("from", SpTime.db(from)).param("to", SpTime.db(to))
                .query((rs, i) -> {
                    Totals t = new Totals(rs.getLong("completed_count"), rs.getLong("gross_cents"), rs.getLong("shop_cents"),
                            rs.getLong("professional_cents"));
                    return new ProfessionalLine(
                            new ProfessionalPublic(rs.getObject("id", UUID.class), rs.getString("name"), rs.getString("photo_url")),
                            m.manager() ? t : t.withoutShop());
                })
                .list();
        Totals totals = m.manager() ? Totals.ZERO : Totals.ZERO.withoutShop();
        for (ProfessionalLine l : lines) {
            totals = totals.plus(l.totals());
        }
        return new MonthlyCash(month.toString(), totals, lines);
    }

    public ProfessionalCash professional(UUID barbershopId, UUID professionalId, String monthParam) {
        MembershipView m = access.member(barbershopId);
        access.requireSelfOrManager(m, professionalId); // profissional pedindo a linha de outro: 403
        YearMonth month = parseMonth(monthParam);
        // Desativado continua com histórico: busca sem filtrar "active".
        ProfessionalRow p = professionals.find(barbershopId, professionalId).orElseThrow(ApiException::notFound);
        List<BookingRow> rows = bookings.completedForProfessional(barbershopId, professionalId, monthStart(month),
                monthStart(month.plusMonths(1)));
        Totals totals = Totals.ZERO;
        for (BookingRow r : rows) {
            totals = totals.plus(new Totals(1, r.priceCents(), (long) r.shopCents(), r.professionalCents()));
        }
        if (!m.manager()) {
            totals = totals.withoutShop();
        }
        return new ProfessionalCash(month.toString(), new ProfessionalPublic(p.id(), p.name(), p.photoUrl()), totals,
                rows.stream().map(r -> r.staffView(m)).toList());
    }
}
