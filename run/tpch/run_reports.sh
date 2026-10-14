#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_timer "tpch/run_reports" "results/tpch" "run_reports"

rm -rf "${ROOT}/reports/tpch"
mkdir -p "${ROOT}/reports/tpch"

DBMS="${1:-PostgreSQL}"

python3 "${ROOT}/scripts/common/query_layer/exp3_Reports/report.py" \
    --dataset tpch \
    --dbms "${DBMS}" \
    --results-dir "${ROOT}/results/tpch" \
    --output-dir "${ROOT}/reports/tpch" \
    --quiet

echo "----------------->> Comparison tpch <<-----------------"

python3 "${ROOT}/scripts/common/query_layer/exp3_Reports/report.py" \
    --dataset tpch \
    --dbms "${DBMS}" \
    --results-dir "${ROOT}/results/tpch" \
    --output-dir "${ROOT}/reports/tpch" \
    --summary-only
