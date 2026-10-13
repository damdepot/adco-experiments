#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${ROOT}/reports/stats"
mkdir -p "${ROOT}/reports/stats"

DBMS="${1:-PostgreSQL}"

python3 "${ROOT}/scripts/common/query_layer/exp3_Reports/report.py" \
    --dataset stats \
    --dbms "${DBMS}" \
    --results-dir "${ROOT}/results/stats" \
    --output-dir "${ROOT}/reports/stats"

echo "----------------->> Comparison stats <<-----------------"
