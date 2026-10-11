#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

rm -rf "${ROOT}/reports/adco_only"
mkdir -p "${ROOT}/reports/adco_only"

CMDRunReports="${ROOT}/scripts/adco_only/run_report.sh"

"${CMDRunReports}" "$@"
