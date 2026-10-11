#!/bin/bash

set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${EXP_PATH}/reports/db_layer"
mkdir -p "${EXP_PATH}/reports/db_layer"

CMDRunReports="${EXP_PATH}/scripts/db_layer/exp2_Reports/run_report.sh"

"$CMDRunReports" "$@"
