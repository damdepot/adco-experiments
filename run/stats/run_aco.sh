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
cd "${ROOT}"

# clean original results
rm -rf results/stats/aco
mkdir -p results/stats/aco/benchmarks

rm -rf out/query_layer/ACo-results
mkdir -p out/query_layer/ACo-results

export iteration=5
export result_dir="results/stats/aco"
export result_benchmark_path="results/stats/aco/benchmarks"
export result_output_path="out/query_layer/ACo-results"

CMDADCo=./scripts/stats/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/stats/exp2_Baselines/runExperiment2-Workload.sh

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
    $CMDRunWorkload stats PostgreSQL ${model} aco
else
    echo 'WARNING: ACo rewrite pipeline failed; skipping its workload measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
./scripts/stats/exp3_Reports/run_report.sh stats PostgreSQL
