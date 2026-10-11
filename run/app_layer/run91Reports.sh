#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

rm -rf reports/app_layer
mkdir -p reports/app_layer

CMDRunReports=./scripts/app_layer/exp2_Reports/run_report.sh

$CMDRunReports "$@"
