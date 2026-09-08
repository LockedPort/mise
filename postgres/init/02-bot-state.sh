#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname einkauf <<-EOSQL
    SET ROLE einkauf;
    CREATE TABLE IF NOT EXISTS bot_state (
      id           smallint primary key default 1 check (id = 1),
      paused       boolean not null default false,
      paused_until date,
      updated_at   timestamptz not null default now()
    );
    INSERT INTO bot_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
EOSQL
