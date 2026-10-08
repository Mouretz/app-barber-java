-- Regra do PO (08/10): duração do serviço só em múltiplos de 30 min (30, 60, 90...), até 8 h.
-- A API já recusa com 422 VALIDATION_ERROR; esta CHECK garante o mesmo no banco.
-- A CHECK antiga (5 a 480) fica: esta é mais estreita e as duas valem juntas.
-- Seed de dev usa 30/30/60, então nada existente viola a regra. Não mexe em bookings:
-- a duração gravada no agendamento é histórica.
ALTER TABLE services
    ADD CONSTRAINT ck_services_duration_grid_30
        CHECK (duration_minutes BETWEEN 30 AND 480 AND duration_minutes % 30 = 0);
