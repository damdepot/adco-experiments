#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DATE="${1:-$(date +%Y-%m-%d)}"

if [[ -z "${DATE}" || "${DATE}" == *"/"* || "${DATE}" == *".."* || "${DATE}" == -* ]]; then
  echo "Usage: run/data/backup_results.sh [date]" >&2
  exit 1
fi

if [[ ! -d "${ROOT}/results" ]]; then
  echo "error: ${ROOT}/results not found or not a directory" >&2
  exit 1
fi

mkdir -p "${ROOT}/backups"
rm -rf "${ROOT}/backups/${DATE}"
cp -a "${ROOT}/results" "${ROOT}/backups/${DATE}"

echo "Backup saved to: backups/${DATE}"
