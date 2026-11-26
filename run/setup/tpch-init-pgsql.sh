#!/bin/bash

root_path="$(cd "$(dirname "$0")/../.." && pwd)"

env_file="${root_path}/.env"
if [ -f "$env_file" ]; then
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
fi

psql_data_path="${POSTGRES_DATA_DIR:-${POSTGRES_DATA_PATH:-${PG_DATA_PATH:-${PGDATA:-/var/lib/postgresql/data}}}}"
psql_bin_path="${POSTGRES_BIN_DIR:-${POSTGRES_BIN_PATH:-${PG_BIN_PATH:-${POSTGRES_BIN:-/usr/lib/postgresql/14/bin}}}}"

if [ -d "${psql_bin_path}/bin" ]; then
    psql_bin_dir="${psql_bin_path}/bin"
else
    psql_bin_dir="${psql_bin_path}"
fi

# Skip when pointed at a remote/managed DB (mirrors the callers' guard in
# runExperiment2-*.sh): there is no local server to restart here.
_pg_host="${PGHOST:-${POSTGRES_HOST:-}}"
case "${_pg_host}" in
    ''|localhost|127.0.0.1) ;;
    *) echo "initpgSQL: PGHOST/POSTGRES_HOST='${_pg_host}' is remote; skipping local restart." >&2; exit 0 ;;
esac

# No local server binaries (e.g. inside the adcoexp container where Postgres
# runs as the separate pgdb service): nothing to restart, skip quietly.
if [ ! -x "${psql_bin_dir}/pg_ctl" ]; then
    echo "initpgSQL: no local pg_ctl at ${psql_bin_dir}; assuming managed/remote Postgres, skipping restart." >&2
    exit 0
fi

${psql_bin_dir}/pg_ctl -D "${psql_data_path}" stop || true
${psql_bin_dir}/postgres -D "${psql_data_path}" &
