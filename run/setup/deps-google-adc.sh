#!/bin/bash

set -euo pipefail

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${root_path}"

if [ ! -f .env ]; then
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
done < .env

if [ -z "${GOOGLE_CLOUD_PROJECT:-}" ]; then
    echo "Error: GOOGLE_CLOUD_PROJECT is empty in .env" >&2
    exit 1
fi

echo "Configuring ADC for project: ${GOOGLE_CLOUD_PROJECT}"
# Replace the upstream interactive project prompt with the .env value, but keep
# the terminal as stdin so `gcloud auth application-default login` can still
# drive the browser OAuth flow.
bash <(curl -sSL \
https://storage.googleapis.com/cloud-samples-data/adc/setup_adc.sh \
| sed "s/^read -p \"Project ID: \" PROJECT_ID\$/PROJECT_ID=\"\${GOOGLE_CLOUD_PROJECT}\"/")