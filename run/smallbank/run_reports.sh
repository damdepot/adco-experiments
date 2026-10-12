#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${ROOT}/reports/smallbank"
mkdir -p "${ROOT}/reports/smallbank"

# DBMS override passthrough: "$1" if given, else postgres (matches each
# run_report.sh's "${2:-postgres}" default).
python3 "${ROOT}/scripts/common/app_layer/exp2_Reports/report.py" \
    --systems baseline,adco,aco,py-dbridge,dco,agenttune,gptuner,ottertune \
    --workload smallbank \
    --dbms "${1:-postgres}" \
    --results-dir "${ROOT}/results" \
    --output-dir "${ROOT}/reports/smallbank" \
    --quiet

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${ROOT}/results/smallbank" "${ROOT}/scripts/_lib/run_comparison.sh"
