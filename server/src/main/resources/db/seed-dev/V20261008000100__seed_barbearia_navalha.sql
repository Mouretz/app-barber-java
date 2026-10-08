-- Seed de DESENVOLVIMENTO (só entra no perfil "dev": spring.flyway.locations em application-dev.yml).
-- Mesmos dados e ids do mock do app (app/lib/data/mock/mock_seed.dart, CT-00-33):
-- Barbearia Navalha, Caio (profissional e gerente), Helena (profissional), Corte 30/R$ 40,
-- Barba 30/R$ 30, Corte + Barba 60/R$ 60, e os clientes João Almeida e Rafael Souza.
--
-- Senha dos logins de dev: "navalha-dev-123" (só desenvolvimento; está aqui como hash BCrypt).
-- Nunca usar este seed em produção.

INSERT INTO barbershops (id, name, neighborhood, city, address, phone, default_professional_percent)
VALUES ('6f1c2a10-0000-4000-8000-000000000001', 'Barbearia Navalha', 'Pinheiros', 'São Paulo',
        'Rua dos Pinheiros, 1000 · Pinheiros, São Paulo', '1130000000', 60);

INSERT INTO services (id, barbershop_id, name, duration_minutes, price_cents) VALUES
    ('6f1c2a10-0000-4000-8000-0000000000a1', '6f1c2a10-0000-4000-8000-000000000001', 'Corte', 30, 4000),
    ('6f1c2a10-0000-4000-8000-0000000000a2', '6f1c2a10-0000-4000-8000-000000000001', 'Barba', 30, 3000),
    ('6f1c2a10-0000-4000-8000-0000000000a3', '6f1c2a10-0000-4000-8000-000000000001', 'Corte + Barba', 60, 6000);

INSERT INTO professionals (id, barbershop_id, name) VALUES
    ('6f1c2a10-0000-4000-8000-0000000000b1', '6f1c2a10-0000-4000-8000-000000000001', 'Caio'),
    ('6f1c2a10-0000-4000-8000-0000000000b2', '6f1c2a10-0000-4000-8000-000000000001', 'Helena');

INSERT INTO staff_users (id, name, email, password_hash) VALUES
    ('6f1c2a10-0000-4000-8000-0000000000f1', 'Caio', 'caio@navalha.dev',
     '$2a$10$XzhFZClFA9dOcw4ylJ0/cefuPdH04H.zrYV63/Y0czuKmxo5AhGwG'),
    ('6f1c2a10-0000-4000-8000-0000000000f2', 'Helena', 'helena@navalha.dev',
     '$2a$10$XzhFZClFA9dOcw4ylJ0/cefuPdH04H.zrYV63/Y0czuKmxo5AhGwG');

-- Caio é gerente e profissional; Helena só profissional.
INSERT INTO memberships (barbershop_id, user_id, is_manager, professional_id) VALUES
    ('6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000f1', true, '6f1c2a10-0000-4000-8000-0000000000b1'),
    ('6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000f2', false, '6f1c2a10-0000-4000-8000-0000000000b2');

-- Expediente (igual ao mock). Caio: segunda a sábado, 08:00–19:00.
-- Helena: terça a domingo, 10:00–14:00 e 15:00–21:00.
INSERT INTO working_hours_versions (id, barbershop_id, professional_id, valid_from) VALUES
    ('6f1c2a10-0000-4000-8000-000000000101', '6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000b1', DATE '2026-01-01'),
    ('6f1c2a10-0000-4000-8000-000000000102', '6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000b2', DATE '2026-01-01');

INSERT INTO working_hours_windows (barbershop_id, version_id, weekday, start_minute, end_minute)
SELECT '6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-000000000101', d, 8 * 60, 19 * 60
  FROM generate_series(1, 6) AS d;

INSERT INTO working_hours_windows (barbershop_id, version_id, weekday, start_minute, end_minute)
SELECT '6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-000000000102', d, w.s, w.e
  FROM generate_series(2, 7) AS d
 CROSS JOIN (VALUES (10 * 60, 14 * 60), (15 * 60, 21 * 60)) AS w(s, e);

-- Clientes: o id da ficha da Navalha é o mesmo do mock (é o id que a Casa vê).
-- João: sem aparelho (o primeiro aparelho real que agendar com o telefone dele fica preso).
-- Rafael: preso a um aparelho fictício (SHA-256 do UUID de dev 6f1c2a10-0000-4000-8000-0000000000dd),
-- para testar 409 PHONE_ON_OTHER_DEVICE com o telefone dele.
INSERT INTO clients (id, phone, device_code_hash) VALUES
    ('6f1c2a10-0000-4000-8000-0000000000c1', '5511987654321', NULL),
    ('6f1c2a10-0000-4000-8000-0000000000c2', '5521912345678', '734977468ac2517daea6b223cad18dddbdc705762a43f5d71b4beda3d2262136');

INSERT INTO client_profiles (id, barbershop_id, client_id, name) VALUES
    ('6f1c2a10-0000-4000-8000-0000000000c1', '6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000c1', 'João Almeida'),
    ('6f1c2a10-0000-4000-8000-0000000000c2', '6f1c2a10-0000-4000-8000-000000000001', '6f1c2a10-0000-4000-8000-0000000000c2', 'Rafael Souza');
