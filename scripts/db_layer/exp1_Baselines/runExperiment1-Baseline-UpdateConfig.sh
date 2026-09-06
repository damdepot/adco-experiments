#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../../.." && pwd)"
env_file="${root_path}/.env"

if [ -f "${env_file}" ]; then
    set -a
    . "${env_file}"
    set +a
else
    echo ".env not found at ${env_file}" >&2
    exit 1
fi

prefix="Baseline"

update_db_config() {
    local dir="$1"
    local dbname="${2:-smallbank}"
    local cfg="${dir}/db.config"
    if [ ! -f "${cfg}" ]; then
        if [ -f "${dir}/db.config-example" ]; then
            cp "${dir}/db.config-example" "${cfg}"
        elif [ -f "${dir}/configs/db.config-example" ]; then
            cp "${dir}/configs/db.config-example" "${cfg}"
        else
            echo "no db.config template in ${dir}, skipping"
            return 0
        fi
    fi

    local var pg_host="127.0.0.1" pg_port="5432" pg_user="postgres" pg_password="postgres"
    var="${prefix}_POSTGRES_HOST"; [ -n "${!var}" ] && pg_host="${!var}"
    var="${prefix}_POSTGRES_PORT"; [ -n "${!var}" ] && pg_port="${!var}"
    var="${prefix}_POSTGRES_USER"; [ -n "${!var}" ] && pg_user="${!var}"
    var="${prefix}_POSTGRES_PASSWORD"; [ -n "${!var}" ] && pg_password="${!var}"

    MYSQL_USER="${MYSQL_USER:-root}" \
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-root}" \
    MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}" \
    MYSQL_PORT="${MYSQL_PORT:-3306}" \
    POSTGRES_USER="${pg_user}" \
    POSTGRES_PASSWORD="${pg_password}" \
    POSTGRES_HOST="${pg_host}" \
    POSTGRES_PORT="${pg_port}" \
    DBNAME="${dbname}" \
    python3 - "${cfg}" <<'PY'
import configparser, os, sys
cfg = sys.argv[1]
c = configparser.ConfigParser()
c.read(cfg)

def setsec(sec, host, port, user, pw):
    if sec not in c:
        c.add_section(sec)
    c[sec]['host'] = host
    c[sec]['port'] = port
    c[sec]['user'] = user
    c[sec]['password'] = pw
    c[sec]['database'] = os.environ['DBNAME']

setsec('mysql', os.environ['MYSQL_HOST'], os.environ['MYSQL_PORT'],
       os.environ['MYSQL_USER'], os.environ['MYSQL_PASSWORD'])
setsec('postgres', os.environ['POSTGRES_HOST'], os.environ['POSTGRES_PORT'],
       os.environ['POSTGRES_USER'], os.environ['POSTGRES_PASSWORD'])

with open(cfg, 'w') as f:
    c.write(f)
print('updated', cfg)
PY
}


echo '-------------------<< Updating smallbank db.config >>-------------------'
update_db_config "${root_path}/workload/apps/smallbank"

echo '-------------------<< Updating tpcc db.config >>-------------------'
update_db_config "${root_path}/workload/apps/tpcc" tpcc
