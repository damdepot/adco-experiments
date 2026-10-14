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

# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpch/run_baseline" "results/tpch/baseline" "baseline"
cd "${ROOT}"

# clean baseline results
rm -rf results/tpch/baseline
mkdir -p results/tpch/baseline/benchmarks

export iteration=2
CMDBaseline=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Baseline.sh

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for TPCH dataset >>-------------------'
$CMDBaseline tpch PostgreSQL 1
