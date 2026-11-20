#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_timer "smallbank/run_report_performance" "results/smallbank" "run_report_performance"

rm -rf "${ROOT}/reports/smallbank"
mkdir -p "${ROOT}/reports/smallbank"

# DBMS override passthrough: "$1" if given, else postgres (matches each
# run_report.sh's "${2:-postgres}" default).
python3 "${ROOT}/scripts/common/app_layer/exp2_Reports/report.py" \
    --systems baseline,py-dbridge,naive-llm,ottertune,gptuner,agenttune,naive-llm-agenttune,agenttune-naive-llm,aco,dco,adco \
    --workload smallbank \
    --dbms "${1:-postgres}" \
    --results-dir "${ROOT}/results" \
    --output-dir "${ROOT}/reports/smallbank" \
    --quiet

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${ROOT}/results/smallbank" "${ROOT}/scripts/_lib/run_comparison.sh"
