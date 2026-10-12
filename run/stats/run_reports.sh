#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-3}"
export DURATION="${DURATION:-60}"
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"

# Single-writer: reports run under the same lock as measurements.
bench_lock "${ROOT}"
cd "${ROOT}"

rm -rf reports/stats
mkdir -p reports/stats

CMDRunReports=./scripts/stats/exp3_Reports/run_report.sh

$CMDRunReports "$@"
