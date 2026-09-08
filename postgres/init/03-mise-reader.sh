#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    CREATE USER mise_reader WITH PASSWORD '${MISE_READER_PASSWORD}';
    GRANT CONNECT ON DATABASE mealie TO mise_reader;
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname mealie <<-EOSQL
    GRANT USAGE ON SCHEMA public TO mise_reader;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO mise_reader;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT SELECT ON TABLES TO mise_reader;
EOSQL
