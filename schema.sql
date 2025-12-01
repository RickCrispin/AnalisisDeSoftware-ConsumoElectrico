-- 0. Habilitar extensiones (ejecutar como superuser)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS timescaledb;


-- 1. Esquema base
CREATE SCHEMA IF NOT EXISTS energy;
SET search_path = energy, public;


-- 2. Tabla users
CREATE TABLE IF NOT EXISTS users (
  user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username VARCHAR(100) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login TIMESTAMPTZ
);


-- 3. Tabla homes
CREATE TABLE IF NOT EXISTS homes (
  home_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(150) NOT NULL,
  address TEXT,
  timezone VARCHAR(64) DEFAULT 'America/Lima',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 4. Relación users <-> homes
CREATE TABLE IF NOT EXISTS user_home (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  home_id UUID NOT NULL REFERENCES homes(home_id) ON DELETE CASCADE,
  role VARCHAR(32) NOT NULL DEFAULT 'owner', -- owner, member, viewer
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, home_id)
);


-- 5. devices
CREATE TABLE IF NOT EXISTS devices (
  device_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  serial VARCHAR(150) UNIQUE,
  model VARCHAR(100),
  type VARCHAR(50), -- ct_clamp, smart_plug, etc
  home_id UUID REFERENCES homes(home_id) ON DELETE SET NULL,
  meta JSONB,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 6. readings (time-series) -> hypertable
CREATE TABLE IF NOT EXISTS readings (
  reading_id BIGSERIAL NOT NULL,
  device_id UUID NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  ts TIMESTAMPTZ NOT NULL,
  power_w NUMERIC(12,3) NULL,
  voltage NUMERIC(10,3) NULL,
  current_a NUMERIC(10,3) NULL,
  raw_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (reading_id)
);


SELECT create_hypertable('energy.readings', 'ts', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);


-- Indexes para lectura
CREATE INDEX IF NOT EXISTS idx_readings_device_ts ON readings(device_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_readings_ts ON readings(ts DESC);


-- 7. events
CREATE TABLE IF NOT EXISTS events (
  event_id BIGSERIAL PRIMARY KEY,
  home_id UUID REFERENCES homes(home_id) ON DELETE CASCADE,
  device_id UUID REFERENCES devices(device_id) ON DELETE SET NULL,
  event_type VARCHAR(100) NOT NULL,
  severity VARCHAR(20) DEFAULT 'info',
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 8. recommendations
CREATE TABLE IF NOT EXISTS recommendations (
  rec_id BIGSERIAL PRIMARY KEY,
  home_id UUID REFERENCES homes(home_id) ON DELETE CASCADE,
  device_id UUID REFERENCES devices(device_id) ON DELETE SET NULL,
  rec_text TEXT NOT NULL,
  rec_type VARCHAR(64),
  score NUMERIC(5,3),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  applied BOOLEAN DEFAULT false
);


-- 9. notifications
CREATE TABLE IF NOT EXISTS notifications (
  notif_id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
  home_id UUID REFERENCES homes(home_id) ON DELETE CASCADE,
  channel VARCHAR(32) NOT NULL, -- push, email, sms
  payload JSONB,
  status VARCHAR(32) DEFAULT 'pending', -- pending, sent, failed
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 10. reports metadata
CREATE TABLE IF NOT EXISTS reports (
  report_id BIGSERIAL PRIMARY KEY,
  home_id UUID REFERENCES homes(home_id) ON DELETE CASCADE,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  file_path VARCHAR(1024),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 11. Materialized table for daily aggregates (optional)
CREATE TABLE IF NOT EXISTS daily_consumption (
  id BIGSERIAL PRIMARY KEY,
  home_id UUID NOT NULL,
  date DATE NOT NULL,
  total_energy_wh NUMERIC(18,3) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(home_id, date)
);


-- 12. Roles de ejemplo (crear si no existen)
-- Nota: Recomendado ejecutar como superuser / admin DB
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_write') THEN
    CREATE ROLE app_write LOGIN PASSWORD 'change_me' NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_readonly') THEN
    CREATE ROLE app_readonly LOGIN PASSWORD 'change_me' NOINHERIT;
  END IF;
END$$;
