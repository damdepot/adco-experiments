#!/bin/bash

# Regenerate the API-keys and DB-config YAMLs of both baselines from .env.
# Edit .env first, then: ./run/setup/stats-update-configs.sh
#
# Files rewritten (they are untracked templates, safe to regenerate):
#   baselines/ReSequel/src/main/python/APIKeys.yaml
#   baselines/ReSequel/src/main/python/DBConfig.yaml
#   baselines/R-Bot/my_rewriter/APIKeys.yaml
#   baselines/R-Bot/my_rewriter/DBConfig.yaml
#   baselines/ADCo/.env
#   workload/src/DBConfig.yaml

set -euo pipefail

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${root_path}"

if [ ! -f .env ]; then
    echo "Error: .env not found in ${root_path}. See README.md." >&2
    exit 1
fi

# Parse .env manually (values are taken literally, so keys containing
# quotes/$/backticks are safe — unlike `source`).
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
done < .env

# Escape single quotes for YAML single-quoted scalars.
esc() { sed "s/'/''/g" <<< "${1:-}"; }

LITELLM_API_KEY="${LITELLM_API_KEY:-${LITELLM_MASTER_KEY:-}}"
LITELLM_BASE_URL="${LITELLM_BASE_URL:-http://litellm:4000}"

for var in OPENAI_API_KEY GROQ_API_KEY LITELLM_API_KEY; do
    if [ -z "${!var:-}" ]; then
        echo "Warning: $var is empty in .env; key left blank."
    fi
done

for var in GOOGLE_GENAI_USE_VERTEXAI GOOGLE_CLOUD_PROJECT GOOGLE_CLOUD_LOCATION; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set in .env." >&2
        exit 1
    fi
done

write_apikeys() {
    cat > "$1" <<EOF
---

- llm_platform: OpenAI
  key_1: '$(esc "$OPENAI_API_KEY")'

- llm_platform: Groq
  key_1: '$(esc "$GROQ_API_KEY")'

- llm_platform: Google
  key_1: '$(esc "$LITELLM_API_KEY")'
  base_url: '$(esc "$LITELLM_BASE_URL")'
EOF
}

write_dbconfig() {
    cat > "$1" <<EOF
---

- database: Postgres
  user: '$(esc "$POSTGRES_USER")'
  password: '$(esc "$POSTGRES_PASSWORD")'
  host: '$(esc "$POSTGRES_HOST")'
  port: ${POSTGRES_PORT:-5432}
EOF
}

# Workload harness DB config (used by workload/src/main.py for measuring).
write_workload_dbconfig() {
    cat > "$1" <<EOF
---

- database: Postgres
  user: '$(esc "$POSTGRES_USER")'
  password: '$(esc "$POSTGRES_PASSWORD")'
  host: '$(esc "$POSTGRES_HOST")'
  port: ${POSTGRES_PORT:-5432}


- database: MySQL
  user: '$(esc "${MYSQL_USER:-admin}")'
  password: '$(esc "${MYSQL_PASSWORD:-admin}")'
  host: '$(esc "${MYSQL_HOST:-127.0.0.1}")'
  port: ${MYSQL_PORT:-3306}
EOF
}

write_adco_env() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
GOOGLE_GENAI_USE_VERTEXAI=$GOOGLE_GENAI_USE_VERTEXAI
GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
GOOGLE_CLOUD_LOCATION=$GOOGLE_CLOUD_LOCATION
EOF
}

echo '-------------------<< Updating ReSequel db.config and API keys >>-------------------'
write_apikeys baselines/ReSequel/src/main/python/APIKeys.yaml
write_dbconfig baselines/ReSequel/src/main/python/DBConfig.yaml

echo '-------------------<< Updating R-Bot db.config and API keys >>-------------------'
write_apikeys baselines/R-Bot/my_rewriter/APIKeys.yaml
write_dbconfig baselines/R-Bot/my_rewriter/DBConfig.yaml

echo '-------------------<< Updating ADCo .env >>-------------------'
write_adco_env baselines/ADCo/.env

echo '-------------------<< Updating workload DBConfig.yaml >>-------------------'
write_workload_dbconfig workload/src/DBConfig.yaml

echo "Updated API keys and DB configs for ReSequel and R-Bot, and .env for ADCo."
