#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
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
rm -rf results/query-tpcc/aco
mkdir -p results/query-tpcc/aco/benchmarks

rm -rf out/query_layer/ACo-results
mkdir -p out/query_layer/ACo-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-tpcc"
export result_dir="results/query-tpcc/aco"
export result_benchmark_path="results/query-tpcc/aco/benchmarks"
export result_output_path="out/query_layer/ACo-results"

CMDADCo=./scripts/common/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"


### ACo (Rewrite-only)
### ******************
aco_pipeline() {
    echo '-------------------<< Compiling TPCC dataset (ACo) >>-------------------'
    $CMDADCo Compile tpcc PostgreSQL 1 ${model} aco
    echo '-------------------<< Generating ACo rewrite queries for TPCC dataset >>-------------------'
    $CMDADCo Rewrite tpcc PostgreSQL 1 ${model} aco
    echo '-------------------<< Decompiling rewrite queries for TPCC dataset (ACo) >>-------------------'
    $CMDADCo Decompile tpcc PostgreSQL 1 ${model} aco
    echo '-------------------<< Verifying rewrite queries for TPCC dataset (ACo) >>-------------------'
    $CMDADCo Verify tpcc PostgreSQL 1 ${model} aco
}

if aco_pipeline; then
    echo '-------------------<< Running workload for TPCC dataset (ACo) >>-------------------'
    $CMDRunWorkload tpcc PostgreSQL ${model} aco
else
    echo 'WARNING: ACo rewrite pipeline failed; skipping its workload measurement.' >&2
fi
