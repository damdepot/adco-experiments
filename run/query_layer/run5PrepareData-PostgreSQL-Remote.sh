#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
data_path="${root_path}/data/stats"
workload_path="${root_path}/workload/databases/PostgreSQL/stats"

env_file="${root_path}/.env"
if [ ! -f "$env_file" ]; then
    echo "Error: .env not found in ${root_path}. See README.md." >&2
    exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf -v "$key" '%s' "$value"
    export "$key"
done < "$env_file"

export PGHOST="${POSTGRES_HOST:-db}"
export PGPORT="${POSTGRES_PORT:-5432}"
export PGUSER="${POSTGRES_USER:-postgres}"
export PGPASSWORD="${POSTGRES_PASSWORD:-postgres}"

echo '-------------------<< Preparing STATS database >>-------------------'
dropdb --if-exists stats
createdb stats

cd "${data_path}"
psql -d stats -f "${workload_path}/schema.sql"
psql -d stats -f "${workload_path}/import_remote.sql"
psql -d stats -f "${workload_path}/index.sql"

echo '-------------------<< STATS database (Remote Compose PostgreSQL service) is ready >>-------------------'
