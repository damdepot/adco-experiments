#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
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
    local dbname="${2-adcodb}"
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
    MYSQL_USER="${MYSQL_USER:-root}" \
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-root}" \
    MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}" \
    MYSQL_PORT="${MYSQL_PORT:-3306}" \
    POSTGRES_USER="${POSTGRES_USER:-postgres}" \
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}" \
    POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}" \
    POSTGRES_PORT="${POSTGRES_PORT:-5432}" \
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
    if os.environ.get('DBNAME'):
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

write_adco_env() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
GOOGLE_GENAI_USE_VERTEXAI=$GOOGLE_GENAI_USE_VERTEXAI
GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
GOOGLE_CLOUD_LOCATION=$GOOGLE_CLOUD_LOCATION
GOOGLE_API_KEY=$GOOGLE_API_KEY
EOF
echo "updated $1"
}

update_agenttune_config() {
    local dir="$1"
    local cfg="${dir}/config.ini"
    if [ ! -f "${cfg}" ]; then
        if [ -f "${dir}/config.ini-example" ]; then
            cp "${dir}/config.ini-example" "${cfg}"
        else
            echo "no config.ini template in ${dir}, skipping"
            return 0
        fi
    fi
    GOOGLE_API_KEY="${GOOGLE_API_KEY:-}" \
    PG_USER="${POSTGRES_USER:-postgres}" \
    PG_PASSWORD="${POSTGRES_PASSWORD:-postgres}" \
    PG_HOST="${POSTGRES_HOST:-127.0.0.1}" \
    PG_PORT="${POSTGRES_PORT:-5432}" \
    python3 - "${cfg}" <<'PY'
import configparser, os, sys
cfg = sys.argv[1]
c = configparser.ConfigParser()
c.optionxform = str
c.read(cfg)

knob = c['knob selector']
knob['api_key'] = os.environ['GOOGLE_API_KEY']
knob['base_url'] = 'https://generativelanguage.googleapis.com/v1beta/openai/'
knob['model'] = 'gemini-3.5-flash-lite'
knob['database_kernel'] = 'PostgreSQL 17'
knob['database_scale'] = '2GB'
knob['hardware'] = '2 cores, 2 GB RAM'

pruner = c['range pruner']
pruner['model'] = 'gemini-3.5-flash-lite'

rec = c['configuration recommender']
rec['model'] = 'gemini-3.5-flash-lite'
rec['dbms'] = 'postgresql'
rec['DB_RestartMethod'] = 'docker'
rec['PG_ContainerName'] = 'adcoexp-db'
rec['PG_RestartCommand'] = 'docker restart adcoexp-db'
rec['DB_User'] = os.environ['PG_USER']
rec['DB_Password'] = os.environ['PG_PASSWORD']
rec['DB_Host'] = os.environ['PG_HOST']
rec['DB_Name'] = 'agenttune'
rec['DB_Port'] = os.environ['PG_PORT']
rec['benchmark'] = 'SYSBENCH'

with open(cfg, 'w') as f:
    c.write(f)
print('updated', cfg)
PY
}


echo '-------------------<< Updating smallbank db.config >>-------------------'
update_db_config "${root_path}/workload/apps/smallbank" smallbank

echo '-------------------<< Updating tpcc db.config >>-------------------'
update_db_config "${root_path}/workload/apps/tpcc" tpcc

echo '-------------------<< Updating ADCo db.config >>-------------------'
update_db_config "${root_path}/baselines/ADCo" ""

echo '-------------------<< Updating ADCo .env >>-------------------'
write_adco_env "${root_path}/baselines/ADCo/.env"

echo '-------------------<< Updating AgentTune config.ini >>-------------------'
update_agenttune_config "${root_path}/baselines/AgentTune"