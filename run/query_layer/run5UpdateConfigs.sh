#!/bin/bash

# Regenerate the API-keys and DB-config YAMLs of both baselines from .env.
# Edit .env first, then: ./run/query_layer/run6UpdateConfigs.sh
#
# Files rewritten (they are untracked templates, safe to regenerate):
#   baselines/ReSequel/src/main/python/APIKeys.yaml
#   baselines/ReSequel/src/main/python/DBConfig.yaml
#   baselines/R-Bot/my_rewriter/APIKeys.yaml
#   baselines/R-Bot/my_rewriter/DBConfig.yaml
#   baselines/ADCo/src/rewriter/.env

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
    key="${line%%=*}"
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

for var in OPENAI_API_KEY GROQ_API_KEY GOOGLE_API_KEY; do
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
  key_1: '$(esc "$GOOGLE_API_KEY")'
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

write_adco_env() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
GOOGLE_GENAI_USE_VERTEXAI=$GOOGLE_GENAI_USE_VERTEXAI
GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
GOOGLE_CLOUD_LOCATION=$GOOGLE_CLOUD_LOCATION
GOOGLE_API_KEY=$GOOGLE_API_KEY
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

echo "Updated API keys and DB configs for ReSequel and R-Bot, and .env for ADCo."
