#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${ROOT}/reports/tpcc/app_layer" "${ROOT}/reports/tpcc/db_layer"
mkdir -p "${ROOT}/reports/tpcc/app_layer" "${ROOT}/reports/tpcc/db_layer"

DBMS="${1:-postgres}"

"${ROOT}/scripts/common/app_layer/exp2_Reports/run_report.sh" tpcc "${DBMS}"
"${ROOT}/scripts/common/db_layer/exp2_Reports/run_report.sh" tpcc "${DBMS}"

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${ROOT}/results/tpcc" "${ROOT}/scripts/_lib/run_comparison.sh"
