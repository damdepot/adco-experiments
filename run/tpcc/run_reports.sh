#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${ROOT}/reports/tpcc"
mkdir -p "${ROOT}/reports/tpcc"

DBMS="${1:-postgres}"

python3 "${ROOT}/scripts/common/app_layer/exp2_Reports/report.py" \
    --systems baseline,adco,aco,py-dbridge,dco,agenttune,gptuner,ottertune \
    --workload tpcc \
    --dbms "${DBMS}" \
    --results-dir "${ROOT}/results" \
    --output-dir "${ROOT}/reports/tpcc" \
    --quiet

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${ROOT}/results/tpcc" "${ROOT}/scripts/_lib/run_comparison.sh"
