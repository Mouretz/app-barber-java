-- CortaAqui: domínio multi-barbearia (reescrita).
-- As tabelas antigas (CLIENTS, SCHEDULES) não tinham dado de produção e não cobriam
-- sobreposição parcial (UNIQUE (start_at, end_at)). Saem aqui.
DROP TABLE IF EXISTS schedules;
DROP TABLE IF EXISTS clients;

-- btree_gist: deixa usar "professional_id WITH =" junto com "period WITH &&" no EXCLUDE.
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- unaccent: busca de cliente por nome sem acento ("joao" acha "João").
CREATE EXTENSION IF NOT EXISTS unaccent;

-- ------------------------------------------------------------------ Barbearia
CREATE TABLE barbershops (
    id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name                         varchar(80)  NOT NULL,
    neighborhood                 varchar(80)  NOT NULL,
    city                         varchar(80)  NOT NULL,
    address                      varchar(200) NOT NULL,
    phone                        varchar(20),
    cover_url                    varchar(500),
    -- % padrão do profissional (a casa fica com 100 - isso). Padrão 60/40.
    default_professional_percent smallint     NOT NULL DEFAULT 60
        CHECK (default_professional_percent BETWEEN 0 AND 100),
    created_at                   timestamptz  NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------------ Login da Casa (global)
-- Uma pessoa = um login. Os papéis ficam por barbearia em memberships.
CREATE TABLE staff_users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          varchar(80)  NOT NULL,
    email         varchar(120) NOT NULL CHECK (email = lower(email)),
    -- BCrypt. NULL = login criado pelo gerente que ainda não definiu senha (primeiro acesso fora do MVP).
    password_hash varchar(72)  CHECK (password_hash IS NULL OR password_hash LIKE '$2%'),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uk_staff_users_email UNIQUE (email)
);

CREATE TABLE staff_sessions (
    token_hash char(64)    PRIMARY KEY,           -- SHA-256 do token; o token em si nunca é gravado
    user_id    uuid        NOT NULL REFERENCES staff_users (id),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz
);
CREATE INDEX ix_staff_sessions_user ON staff_sessions (user_id);

-- ------------------------------------------------------------------ Profissional
CREATE TABLE professionals (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id        uuid        NOT NULL REFERENCES barbershops (id),
    name                 varchar(60) NOT NULL,
    photo_url            varchar(500),
    -- Nunca apagado, só desativado.
    active               boolean     NOT NULL DEFAULT true,
    -- NULL = usa o padrão da barbearia.
    professional_percent smallint CHECK (professional_percent BETWEEN 0 AND 100),
    created_at           timestamptz NOT NULL DEFAULT now(),
    deactivated_at       timestamptz,
    CONSTRAINT uk_professionals_tenant UNIQUE (barbershop_id, id)
);

-- Vínculo pessoa x barbearia, com o papel. MANAGER = is_manager; PROFESSIONAL = professional_id preenchido.
CREATE TABLE memberships (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id   uuid    NOT NULL REFERENCES barbershops (id),
    user_id         uuid    NOT NULL REFERENCES staff_users (id),
    is_manager      boolean NOT NULL DEFAULT false,
    professional_id uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uk_memberships_user UNIQUE (barbershop_id, user_id),
    CONSTRAINT uk_memberships_professional UNIQUE (professional_id),
    CONSTRAINT fk_memberships_professional FOREIGN KEY (barbershop_id, professional_id)
        REFERENCES professionals (barbershop_id, id),
    CONSTRAINT ck_memberships_has_role CHECK (is_manager OR professional_id IS NOT NULL)
);

-- ------------------------------------------------------------------ Serviço
CREATE TABLE services (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id    uuid        NOT NULL REFERENCES barbershops (id),
    name             varchar(60) NOT NULL,
    duration_minutes integer     NOT NULL CHECK (duration_minutes BETWEEN 5 AND 480),
    price_cents      integer     NOT NULL CHECK (price_cents >= 0),
    active           boolean     NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uk_services_tenant UNIQUE (barbershop_id, id)
);

-- ------------------------------------------------------------------ Expediente (versionado)
-- Mudar o expediente cria uma versão nova que vale a partir de hoje; dias passados
-- continuam com a versão antiga. Nenhum agendamento é mexido.
CREATE TABLE working_hours_versions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id   uuid        NOT NULL REFERENCES barbershops (id),
    professional_id uuid        NOT NULL,
    valid_from      date        NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uk_working_hours_versions UNIQUE (professional_id, valid_from),
    CONSTRAINT uk_working_hours_versions_tenant UNIQUE (barbershop_id, id),
    CONSTRAINT fk_working_hours_versions_professional FOREIGN KEY (barbershop_id, professional_id)
        REFERENCES professionals (barbershop_id, id)
);

CREATE TABLE working_hours_windows (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id uuid     NOT NULL REFERENCES barbershops (id),
    version_id    uuid     NOT NULL,
    weekday       smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7), -- ISO: 1 = segunda
    -- Minutos desde 00:00 (hora de Brasília). Fim 1440 = 00:00, fim do mesmo dia; nada atravessa a meia-noite.
    start_minute  smallint NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
    end_minute    smallint NOT NULL CHECK (end_minute BETWEEN 1 AND 1440),
    CONSTRAINT ck_working_hours_windows_order CHECK (end_minute > start_minute),
    CONSTRAINT fk_working_hours_windows_version FOREIGN KEY (barbershop_id, version_id)
        REFERENCES working_hours_versions (barbershop_id, id) ON DELETE CASCADE
);
CREATE INDEX ix_working_hours_windows_version ON working_hours_windows (version_id, weekday);

-- ------------------------------------------------------------------ Folga
CREATE TABLE time_off (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id   uuid        NOT NULL REFERENCES barbershops (id),
    professional_id uuid        NOT NULL,
    start_at        timestamptz NOT NULL,
    end_at          timestamptz NOT NULL,
    reason          varchar(120),
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_time_off_order CHECK (end_at > start_at),
    CONSTRAINT fk_time_off_professional FOREIGN KEY (barbershop_id, professional_id)
        REFERENCES professionals (barbershop_id, id)
);
CREATE INDEX ix_time_off_professional ON time_off (professional_id, start_at);

-- ------------------------------------------------------------------ Cliente
-- Cadastro global: um por telefone (é ele que tem o código do aparelho).
CREATE TABLE clients (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Só dígitos: 55 + DDD + número (10 ou 11 dígitos depois do 55).
    phone            varchar(13) NOT NULL,
    -- SHA-256 do código do aparelho. O código é gerado no celular no 1º agendamento e só existe lá.
    -- Prende o telefone a um aparelho; o gerente pode liberar (volta a NULL) para o cliente trocar de celular.
    device_code_hash char(64),
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uk_clients_phone UNIQUE (phone),
    CONSTRAINT uk_clients_device_code UNIQUE (device_code_hash),
    CONSTRAINT ck_clients_phone_format CHECK (phone ~ '^55[1-9]{2}[0-9]{8,9}$')
);

-- Códigos de aparelho liberados pelo gerente: param de valer na hora (401), inclusive para agendar.
CREATE TABLE client_device_releases (
    code_hash           char(64)    PRIMARY KEY,
    client_id           uuid        NOT NULL REFERENCES clients (id),
    barbershop_id       uuid        NOT NULL REFERENCES barbershops (id), -- barbearia do gerente que liberou
    released_by_user_id uuid        NOT NULL REFERENCES staff_users (id),
    released_at         timestamptz NOT NULL DEFAULT now()
);

-- Ficha por barbearia. client_id NULL = cliente de balcão sem telefone.
CREATE TABLE client_profiles (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id uuid         NOT NULL REFERENCES barbershops (id),
    client_id     uuid         REFERENCES clients (id),
    name          varchar(80)  NOT NULL,
    email         varchar(120),
    notes         varchar(500),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uk_client_profiles_client UNIQUE (barbershop_id, client_id),
    CONSTRAINT uk_client_profiles_tenant UNIQUE (barbershop_id, id)
);

-- ------------------------------------------------------------------ Bloqueio
CREATE TABLE blocks (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id      uuid        NOT NULL REFERENCES barbershops (id),
    professional_id    uuid        NOT NULL,
    start_at           timestamptz NOT NULL,
    end_at             timestamptz NOT NULL,
    reason             varchar(120),
    created_by_user_id uuid REFERENCES staff_users (id),
    created_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_blocks_order CHECK (end_at > start_at),
    CONSTRAINT fk_blocks_professional FOREIGN KEY (barbershop_id, professional_id)
        REFERENCES professionals (barbershop_id, id)
);

-- ------------------------------------------------------------------ Agendamento
CREATE TABLE bookings (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    barbershop_id        uuid        NOT NULL REFERENCES barbershops (id),
    professional_id      uuid        NOT NULL,
    service_id           uuid        NOT NULL,
    client_profile_id    uuid        NOT NULL,
    -- Cliente global (para o limite de 2 pelo app somando barbearias). NULL no balcão sem telefone.
    client_id            uuid        REFERENCES clients (id),
    source               varchar(10) NOT NULL CHECK (source IN ('CLIENT_APP', 'STAFF', 'COUNTER')),
    status               varchar(10) NOT NULL DEFAULT 'SCHEDULED'
        CHECK (status IN ('SCHEDULED', 'COMPLETED', 'NO_SHOW', 'CANCELED')),
    start_at             timestamptz NOT NULL,
    end_at               timestamptz NOT NULL,
    -- Gravados na criação: mudar o serviço depois não muda o agendamento.
    service_name         varchar(60) NOT NULL,
    duration_minutes     integer     NOT NULL CHECK (duration_minutes > 0),
    price_cents          integer     NOT NULL CHECK (price_cents >= 0),
    -- Gravados na conclusão.
    professional_percent smallint CHECK (professional_percent BETWEEN 0 AND 100),
    shop_percent         smallint CHECK (shop_percent BETWEEN 0 AND 100),
    professional_cents   integer CHECK (professional_cents >= 0),
    shop_cents           integer CHECK (shop_cents >= 0),
    completed_at         timestamptz,
    no_show_at           timestamptz,
    canceled_by          varchar(6) CHECK (canceled_by IN ('CLIENT', 'STAFF')),
    canceled_at          timestamptz,
    note                 varchar(200),
    idempotency_key      uuid        NOT NULL,
    request_fingerprint  char(64)    NOT NULL,
    created_by_user_id   uuid REFERENCES staff_users (id),
    created_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uk_bookings_idempotency_key UNIQUE (idempotency_key),
    CONSTRAINT uk_bookings_tenant UNIQUE (barbershop_id, id),
    CONSTRAINT fk_bookings_professional FOREIGN KEY (barbershop_id, professional_id)
        REFERENCES professionals (barbershop_id, id),
    CONSTRAINT fk_bookings_service FOREIGN KEY (barbershop_id, service_id)
        REFERENCES services (barbershop_id, id),
    CONSTRAINT fk_bookings_client_profile FOREIGN KEY (barbershop_id, client_profile_id)
        REFERENCES client_profiles (barbershop_id, id),
    CONSTRAINT ck_bookings_duration CHECK (end_at = start_at + make_interval(mins => duration_minutes)),
    CONSTRAINT ck_bookings_app_has_client CHECK (source <> 'CLIENT_APP' OR client_id IS NOT NULL),
    CONSTRAINT ck_bookings_split_only_when_completed CHECK (
        (status = 'COMPLETED') = (professional_percent IS NOT NULL AND shop_percent IS NOT NULL
                                  AND professional_cents IS NOT NULL AND shop_cents IS NOT NULL)),
    CONSTRAINT ck_bookings_split_sums CHECK (
        professional_percent IS NULL OR
        (professional_percent + shop_percent = 100 AND professional_cents + shop_cents = price_cents)),
    CONSTRAINT ck_bookings_canceled_by CHECK ((status = 'CANCELED') = (canceled_by IS NOT NULL))
);
CREATE INDEX ix_bookings_agenda ON bookings (barbershop_id, professional_id, start_at);
CREATE INDEX ix_bookings_client ON bookings (client_id, status, start_at);
CREATE INDEX ix_bookings_profile ON bookings (client_profile_id, start_at);

-- Pedido repetido (Idempotency-Key) em cancelamento e mudança de status.
CREATE TABLE booking_status_requests (
    idempotency_key  uuid PRIMARY KEY,
    barbershop_id    uuid        NOT NULL REFERENCES barbershops (id),
    booking_id       uuid        NOT NULL,
    requested_status varchar(10) NOT NULL CHECK (requested_status IN ('COMPLETED', 'NO_SHOW', 'CANCELED')),
    actor            varchar(6)  NOT NULL CHECK (actor IN ('CLIENT', 'STAFF')),
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_booking_status_requests_booking FOREIGN KEY (barbershop_id, booking_id)
        REFERENCES bookings (barbershop_id, id) ON DELETE CASCADE
);

-- ------------------------------------------------------------------ A trava (sem encaixe duplo)
-- Agendamentos ativos (SCHEDULED e COMPLETED) e bloqueios ocupam a mesma tabela, com um
-- EXCLUDE por profissional. Falta e cancelado saem daqui e liberam o horário.
-- As linhas são mantidas por trigger, então até um INSERT direto no banco passa pela trava.
CREATE TABLE agenda_occupancy (
    id              bigserial PRIMARY KEY,
    barbershop_id   uuid      NOT NULL REFERENCES barbershops (id),
    professional_id uuid      NOT NULL,
    period          tstzrange NOT NULL,
    booking_id      uuid UNIQUE REFERENCES bookings (id) ON DELETE CASCADE,
    block_id        uuid UNIQUE REFERENCES blocks (id) ON DELETE CASCADE,
    CONSTRAINT ck_agenda_occupancy_one_owner CHECK (num_nonnulls(booking_id, block_id) = 1),
    CONSTRAINT ck_agenda_occupancy_not_empty CHECK (NOT isempty(period)),
    CONSTRAINT fk_agenda_occupancy_professional FOREIGN KEY (barbershop_id, professional_id)
        REFERENCES professionals (barbershop_id, id),
    CONSTRAINT ex_agenda_sem_sobreposicao EXCLUDE USING gist (professional_id WITH =, period WITH &&)
);

CREATE FUNCTION bookings_occupancy() RETURNS trigger
    LANGUAGE plpgsql AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status IN ('SCHEDULED', 'COMPLETED') THEN
            INSERT INTO agenda_occupancy (barbershop_id, professional_id, period, booking_id)
            VALUES (NEW.barbershop_id, NEW.professional_id, tstzrange(NEW.start_at, NEW.end_at, '[)'), NEW.id);
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE
    IF (NEW.barbershop_id, NEW.professional_id, NEW.start_at, NEW.end_at)
        IS DISTINCT FROM (OLD.barbershop_id, OLD.professional_id, OLD.start_at, OLD.end_at) THEN
        RAISE EXCEPTION 'agendamento não muda de profissional nem de horário'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_bookings_immutable_slot';
    END IF;
    IF OLD.status <> 'SCHEDULED' AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'status final não muda (% -> %)', OLD.status, NEW.status
            USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_bookings_status_forward_only';
    END IF;
    IF NEW.status IN ('NO_SHOW', 'CANCELED') AND OLD.status NOT IN ('NO_SHOW', 'CANCELED') THEN
        DELETE FROM agenda_occupancy WHERE booking_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tg_bookings_occupancy
    AFTER INSERT OR UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION bookings_occupancy();

CREATE FUNCTION blocks_occupancy() RETURNS trigger
    LANGUAGE plpgsql AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO agenda_occupancy (barbershop_id, professional_id, period, block_id)
        VALUES (NEW.barbershop_id, NEW.professional_id, tstzrange(NEW.start_at, NEW.end_at, '[)'), NEW.id);
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'bloqueio não é editado; desbloqueie e crie outro'
        USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_blocks_immutable';
END;
$$;

CREATE TRIGGER tg_blocks_occupancy
    AFTER INSERT OR UPDATE ON blocks
    FOR EACH ROW EXECUTE FUNCTION blocks_occupancy();
