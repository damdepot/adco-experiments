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
bench_timer "stats/run_aco" "results/stats/aco" "aco"
cd "${ROOT}"
bench_snapshot_seed stats stats_seed ./run/setup/stats-prepare-postgres-remote.sh

# clean original results
rm -rf results/stats/aco
mkdir -p results/stats/aco/benchmarks

rm -rf out/query_layer/ACo-results
mkdir -p out/query_layer/ACo-results

export iteration=2
export result_dir="results/stats/aco"
export result_benchmark_path="results/stats/aco/benchmarks"
export result_output_path="out/query_layer/ACo-results"

CMDADCo=./scripts/common/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"


### ACo (Rewrite-only)
### ******************
aco_pipeline() {
    echo '-------------------<< Compiling Stats-Lite dataset (ACo) >>-------------------'
    $CMDADCo Compile stats PostgreSQL 1 ${model} aco
    echo '-------------------<< Generating ACo rewrite queries for Stats-Lite dataset >>-------------------'
    $CMDADCo Rewrite stats PostgreSQL 1 ${model} aco
    echo '-------------------<< Decompiling rewrite queries for Stats-Lite dataset (ACo) >>-------------------'
    $CMDADCo Decompile stats PostgreSQL 1 ${model} aco
    echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset (ACo) >>-------------------'
    $CMDADCo Verify stats PostgreSQL 1 ${model} aco
}

if aco_pipeline; then
    echo '-------------------<< Running workload for Stats-Lite dataset (ACo) >>-------------------'
    bench_fresh_db stats stats_seed users "${STATS_USERS_ROWS:-40325}"
    python3 "${ROOT}/tools/check_knobs.py"
    $CMDRunWorkload stats PostgreSQL ${model} aco
else
    echo 'WARNING: ACo rewrite pipeline failed; skipping its workload measurement.' >&2
fi
