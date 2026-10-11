#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-8}"
export REPS="${REPS:-3}"
export DURATION="${DURATION:-60}"
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"

# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
cd "${ROOT}"

# clean baseline results
rm -rf results/stats/baseline
mkdir -p results/stats/baseline/benchmarks

export iteration=5
CMDBaseline=./scripts/stats/exp2_Baselines/runExperiment2-Baseline.sh

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for Stats-Lite dataset >>-------------------'
$CMDBaseline stats PostgreSQL 1

echo '-------------------<< Comparison >>-------------------'
./scripts/stats/exp3_Reports/run_report.sh stats PostgreSQL
