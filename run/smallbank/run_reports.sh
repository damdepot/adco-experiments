#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${ROOT}/reports/smallbank/app_layer" "${ROOT}/reports/smallbank/db_layer"
mkdir -p "${ROOT}/reports/smallbank/app_layer" "${ROOT}/reports/smallbank/db_layer"

# DBMS override passthrough: "$1" if given, else postgres (matches each
# run_report.sh's "${2:-postgres}" default).
"${ROOT}/scripts/common/app_layer/exp2_Reports/run_report.sh" smallbank "${1:-postgres}"
"${ROOT}/scripts/common/db_layer/exp2_Reports/run_report.sh" smallbank "${1:-postgres}"

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${ROOT}/results/smallbank" "${ROOT}/scripts/_lib/run_comparison.sh"
