#!/bin/bash

# Regenerate the API-keys and DB-config YAMLs of both baselines from .env.
# Edit .env first, then: ./run6UpdateConfigs.sh
#
# Files rewritten (they are untracked templates, safe to regenerate):
#   baselines/ReSequel/src/main/python/APIKeys.yaml
#   baselines/ReSequel/src/main/python/DBConfig.yaml
#   baselines/R-Bot/my_rewriter/APIKeys.yaml
#   baselines/R-Bot/my_rewriter/DBConfig.yaml

set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "Error: .env not found in $(pwd). See README.md." >&2
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
  user: '$(esc "$PGUSER")'
  password: '$(esc "$PGPASSWORD")'
  host: '$(esc "$PGHOST")'
  port: ${PGPORT:-5432}
EOF
}

write_apikeys baselines/ReSequel/src/main/python/APIKeys.yaml
write_apikeys baselines/R-Bot/my_rewriter/APIKeys.yaml
write_dbconfig baselines/ReSequel/src/main/python/DBConfig.yaml
write_dbconfig baselines/R-Bot/my_rewriter/DBConfig.yaml

echo "Updated API keys and DB configs for ReSequel and R-Bot."
