-- Seed de DESENVOLVIMENTO (só no perfil "dev"). Nunca usar em produção.
-- 1) Marina Costa (nome igual ao mock da Casa): gerente da Barbearia Navalha que NÃO corta. Vínculo com is_manager = true e
--    professional_id NULL; não tem linha em professionals (não aparece na equipe nem na agenda).
--    Login de dev: marina@navalha.dev, com o mesmo hash BCrypt de Caio e Helena
--    (V20261008000100). Não escreva a senha em texto neste arquivo.
-- 2) O atendimento concluído do mock (app/lib/data/mock/mock_seed.dart, id ...d2).

INSERT INTO staff_users (id, name, email, password_hash) VALUES
    ('6f1c2a10-0000-4000-8000-0000000000f3', 'Marina Costa', 'marina@navalha.dev',
     '$2a$10$XzhFZClFA9dOcw4ylJ0/cefuPdH04H.zrYV63/Y0czuKmxo5AhGwG');

INSERT INTO memberships (barbershop_id, user_id, is_manager, professional_id) VALUES
    ('6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000f3', true, NULL);

-- Atendimento concluído do mock: Helena, "Corte + Barba" (60 min, R$ 60), João Almeida pelo app,
-- hoje (em SP) menos 7 dias às 15:00 de SP, fim às 16:00 (o mock usa a duração do serviço).
-- Gravado já COMPLETED com o split de 60/40 (o padrão da casa; Helena não tem % própria):
-- 3600 para a profissional e 2400 para a casa. O INSERT direto passa pelo trigger
-- tg_bookings_occupancy (ocupa a agenda da Helena; não há bloqueio no seed) e pelas CHECKs
-- (duração, split só quando concluído, split soma 100 e price_cents, app com client_id).
-- Data relativa: o Flyway roda este arquivo uma vez, então a data é a do dia em que o banco
-- de dev foi criado.
INSERT INTO bookings (id, barbershop_id, professional_id, service_id, client_profile_id, client_id, source, status,
                      start_at, end_at, service_name, duration_minutes, price_cents,
                      professional_percent, shop_percent, professional_cents, shop_cents, completed_at,
                      idempotency_key, request_fingerprint, created_at)
SELECT '6f1c2a10-0000-4000-8000-0000000000d2'::uuid, '6f1c2a10-0000-4000-8000-000000000001'::uuid,
       '6f1c2a10-0000-4000-8000-0000000000b2'::uuid, '6f1c2a10-0000-4000-8000-0000000000a3'::uuid,
       '6f1c2a10-0000-4000-8000-0000000000c1'::uuid, '6f1c2a10-0000-4000-8000-0000000000c1'::uuid, 'CLIENT_APP', 'COMPLETED',
       s.start_at, s.start_at + interval '60 minutes', 'Corte + Barba', 60, 6000,
       60, 40, 3600, 2400, s.start_at + interval '60 minutes',
       '6f1c2a10-0000-4000-8000-0000000000e2'::uuid, encode(sha256(convert_to('seed-dev:booking:d2', 'UTF8')), 'hex'),
       s.start_at - interval '1 day'
  FROM (SELECT ((((now() AT TIME ZONE 'America/Sao_Paulo')::date - 7) + time '15:00')
                AT TIME ZONE 'America/Sao_Paulo') AS start_at) AS s;
