import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/time/sao_paulo.dart';
import '../../../data/models/booking.dart';
import '../../../theme/theme.dart';
import 'common.dart';

/// Texto do status para o cliente.
String bookingStatusLabel(Booking b) {
  switch (b.status) {
    case BookingStatus.scheduled:
      return 'Agendado';
    case BookingStatus.completed:
      return 'Concluído';
    case BookingStatus.noShow:
      return 'Falta';
    case BookingStatus.canceled:
      return b.canceledByShop ? 'Cancelado pela barbearia' : 'Cancelado';
  }
}

Color bookingStatusColor(CortaTokens t, BookingStatus s) {
  switch (s) {
    case BookingStatus.scheduled:
      return t.statusScheduled;
    case BookingStatus.completed:
      return t.statusCompleted;
    case BookingStatus.noShow:
      return t.statusNoShow;
    case BookingStatus.canceled:
      return t.statusCanceled;
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final t = CortaTokens.of(context);
    final color = bookingStatusColor(t, booking.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          bookingStatusLabel(booking),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Card de um horário (Início e Meus horários).
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.today,
    this.showStatus = true,
    this.footer,
    this.onTap,
  });

  final Booking booking;
  final SpDate today;
  final bool showStatus;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = booking;
    return SurfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatBookingWhen(b.startAt, today),
                  style: text.titleLarge,
                ),
              ),
              if (showStatus) StatusPill(booking: b),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ProAvatar(name: b.professional.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${b.service.name} com ${b.professional.name}',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (b.barbershopName != null) b.barbershopName!,
                        formatCents(b.priceCents),
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}
