#!/bin/bash

root_path="$(cd "$(dirname "$0")/../.." && pwd)"

env_file="${root_path}/.env"
if [ -f "$env_file" ]; then
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
fi

psql_data_path="${POSTGRES_DATA_DIR:-${POSTGRES_DATA_PATH:-${PG_DATA_PATH:-${PGDATA:-/var/lib/postgresql/data}}}}"
psql_bin_path="${POSTGRES_BIN_DIR:-${POSTGRES_BIN_PATH:-${PG_BIN_PATH:-${POSTGRES_BIN:-/usr/lib/postgresql/14/bin}}}}"

if [ -d "${psql_bin_path}/bin" ]; then
    psql_bin_dir="${psql_bin_path}/bin"
else
    psql_bin_dir="${psql_bin_path}"
fi

${psql_bin_dir}/pg_ctl -D "${psql_data_path}" stop
${psql_bin_dir}/postgres -D "${psql_data_path}" &