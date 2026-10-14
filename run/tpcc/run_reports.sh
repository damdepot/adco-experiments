#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_timer "tpcc/run_reports" "results/tpcc" "run_reports"

rm -rf "${ROOT}/reports/tpcc"
mkdir -p "${ROOT}/reports/tpcc"

DBMS="${1:-postgres}"

python3 "${ROOT}/scripts/common/app_layer/exp2_Reports/report.py" \
    --systems baseline,py-dbridge,naive-llm,ottertune,gptuner,agenttune,aco,dco,adco \
    --workload tpcc \
    --dbms "${DBMS}" \
    --results-dir "${ROOT}/results" \
    --output-dir "${ROOT}/reports/tpcc" \
    --quiet

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${ROOT}/results/tpcc" "${ROOT}/scripts/_lib/run_comparison.sh"
