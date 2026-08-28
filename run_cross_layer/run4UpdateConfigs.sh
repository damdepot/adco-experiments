#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${root_path}/.env"

if [ -f "${env_file}" ]; then
    set -a
    . "${env_file}"
    set +a
else
    echo ".env not found at ${env_file}" >&2
    exit 1
fi

update_db_config() {
    local dir="$1"
    local cfg="${dir}/db.config"
    if [ ! -f "${cfg}" ]; then
        if [ -f "${dir}/db.config-example" ]; then
            cp "${dir}/db.config-example" "${cfg}"
        else
            echo "no db.config template in ${dir}, skipping"
            return 0
        fi
    fi
    MYSQL_USER="${MYSQL_USER:-root}" \
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-root}" \
    MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}" \
    MYSQL_PORT="${MYSQL_PORT:-3306}" \
    PGUSER="${PGUSER:-postgres}" \
    PGPASSWORD="${PGPASSWORD:-postgres}" \
    PGHOST="${PGHOST:-127.0.0.1}" \
    PGPORT="${PGPORT:-5432}" \
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
    c[sec]['database'] = 'smallbank'

setsec('mysql', os.environ['MYSQL_HOST'], os.environ['MYSQL_PORT'],
       os.environ['MYSQL_USER'], os.environ['MYSQL_PASSWORD'])
setsec('postgres', os.environ['PGHOST'], os.environ['PGPORT'],
       os.environ['PGUSER'], os.environ['PGPASSWORD'])

with open(cfg, 'w') as f:
    c.write(f)
print('updated', cfg)
PY
}


echo '-------------------<< Updating smallbank db.config >>-------------------'
update_db_config "${root_path}/workload/apps/smallbank"
