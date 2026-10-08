package br.com.cortaaqui.booking;

import br.com.cortaaqui.auth.MembershipView;
import br.com.cortaaqui.common.Phones;
import br.com.cortaaqui.common.SpTime;
import br.com.cortaaqui.team.ProfessionalPublic;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

public record BookingRow(UUID id, UUID barbershopId, String barbershopName, UUID professionalId, String professionalName,
                         String professionalPhotoUrl, UUID serviceId, String serviceName, UUID clientProfileId,
                         String clientName, UUID clientId, String clientPhone, String source, String status,
                         Instant startAt, Instant endAt, int durationMinutes, int priceCents, Integer professionalPercent,
                         Integer shopPercent, Integer professionalCents, Integer shopCents, String canceledBy, String note,
                         Instant createdAt, String requestFingerprint, UUID createdByUserId, boolean overlapsBlock) {

    /** Cliente cancela com 2h ou mais de antecedência (exatamente 2h pode). */
    public static final Duration CLIENT_CANCEL_MIN_NOTICE = Duration.ofHours(2);

    public boolean clientCanCancel(Instant now) {
        return "SCHEDULED".equals(status) && !now.plus(CLIENT_CANCEL_MIN_NOTICE).isAfter(startAt);
    }

    /**
     * Visão da Casa. O profissional que não é gerente não vê a parte da casa (shopPercent);
     * ele vê só o que é dele.
     */
    public BookingView staffView(MembershipView m) {
        return new BookingView(id, barbershopId, barbershopName, status, source, SpTime.sp(startAt), SpTime.sp(endAt),
                new BookingView.Ref(serviceId, serviceName), new ProfessionalPublic(professionalId, professionalName, professionalPhotoUrl),
                new BookingView.ClientRef(clientProfileId, clientName, Phones.display(clientPhone)), priceCents,
                m.manager() ? shopPercent : null, professionalPercent, null, canceledBy, note, SpTime.sp(createdAt), overlapsBlock);
    }

    /** Visão do app Cliente: sem telefone, sem % e sem nota interna da barbearia. */
    public BookingView clientView(Instant now) {
        return new BookingView(id, barbershopId, barbershopName, status, source, SpTime.sp(startAt), SpTime.sp(endAt),
                new BookingView.Ref(serviceId, serviceName), new ProfessionalPublic(professionalId, professionalName, professionalPhotoUrl),
                new BookingView.ClientRefPublic(clientProfileId, clientName), priceCents, null, null,
                clientCanCancel(now), canceledBy, null, SpTime.sp(createdAt), null);
    }
}
