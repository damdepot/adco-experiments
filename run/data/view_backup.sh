#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  echo "Usage: run/data/view_backup.sh <date> [tpcc|smallbank|stats|tpch]" >&2
  if [ -d "${ROOT}/backups" ]; then
    echo "Available dates:" >&2
    ls "${ROOT}/backups" >&2
  fi
}

DATE="${1:-}"
FILTER="${2:-}"

if [[ -z "${DATE}" || "${DATE}" == *"/"* || "${DATE}" == *".."* || "${DATE}" == -* ]]; then
  usage
  exit 1
fi

case "${FILTER}" in
  ""|tpcc|smallbank|stats|tpch) ;;
  *) usage; exit 1 ;;
esac

BACKUP_DIR="${ROOT}/backups/${DATE}"
if [ ! -d "${BACKUP_DIR}" ]; then
  usage
  exit 1
fi

WORKLOADS="tpcc smallbank stats tpch"
if [ -n "${FILTER}" ]; then
  WORKLOADS="${FILTER}"
fi

for w in ${WORKLOADS}; do
  if [ ! -d "${BACKUP_DIR}/${w}" ]; then
    echo "Skipping ${w}: no backup at ${BACKUP_DIR}/${w}"
    continue
  fi
  echo "----------------->> Comparison ${w} <<-----------------"
  if [ "${w}" = "tpcc" ] || [ "${w}" = "smallbank" ]; then
    RESULTS_DIR="${BACKUP_DIR}/${w}" "${ROOT}/scripts/_lib/run_comparison.sh" || true
  else
    python3 "${ROOT}/scripts/common/query_layer/exp3_Reports/report.py" --dataset "${w}" --dbms "PostgreSQL" --results-dir "${BACKUP_DIR}/${w}" --summary-only
  fi
done
