#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
data_path="${root_path}/data/tpch"
workload_path="${root_path}/workload/databases/PostgreSQL/tpch"

env_file="${root_path}/.env"
if [ ! -f "$env_file" ]; then
    echo "Error: .env not found in ${root_path}. See README.md." >&2
    exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    case "$key" in ''|*[!A-Za-z0-9_]* ) continue ;; esac
    value="${line#*=}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf -v "$key" '%s' "$value"
    export "$key"
done < "$env_file"

export PGHOST="${POSTGRES_HOST:-pgdb}"
export PGPORT="${POSTGRES_PORT:-5432}"
export PGUSER="${POSTGRES_USER:-postgres}"
export PGPASSWORD="${POSTGRES_PASSWORD:-postgres}"

echo '-------------------<< Preparing TPCH database >>-------------------'
dropdb --if-exists tpch
createdb tpch

cd "${data_path}"
psql -v ON_ERROR_STOP=1 -d tpch -f "${workload_path}/schema.sql"
# NOTE: import_remote.sql (client-side \copy with paths relative to
# data/tpch) is used instead of import.sql (server-side COPY), because the
# .tbl files live on the experiment host/container, not on the DB server.
psql -v ON_ERROR_STOP=1 -d tpch -f "${workload_path}/import_remote.sql"
psql -v ON_ERROR_STOP=1 -d tpch -f "${workload_path}/add_FK.sql"
psql -v ON_ERROR_STOP=1 -d tpch -f "${workload_path}/index.sql"

echo '-------------------<< TPCH database (Local PostgreSQL service) is ready >>-------------------'
