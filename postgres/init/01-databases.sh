#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    CREATE USER mealie  WITH PASSWORD '${MEALIE_DB_PASSWORD}';
    CREATE DATABASE mealie  OWNER mealie;

    CREATE USER einkauf WITH PASSWORD '${EINKAUF_DB_PASSWORD}';
    CREATE DATABASE einkauf OWNER einkauf;
EOSQL