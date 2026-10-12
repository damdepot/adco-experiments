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
rm -rf results/query-smallbank/aco
mkdir -p results/query-smallbank/aco/benchmarks

rm -rf out/query_layer/ACo-results
mkdir -p out/query_layer/ACo-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-smallbank"
export result_dir="results/query-smallbank/aco"
export result_benchmark_path="results/query-smallbank/aco/benchmarks"
export result_output_path="out/query_layer/ACo-results"

CMDADCo=./scripts/common/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"


### ACo (Rewrite-only)
### ******************
aco_pipeline() {
    echo '-------------------<< Compiling Smallbank dataset (ACo) >>-------------------'
    $CMDADCo Compile smallbank PostgreSQL 1 ${model} aco
    echo '-------------------<< Generating ACo rewrite queries for Smallbank dataset >>-------------------'
    $CMDADCo Rewrite smallbank PostgreSQL 1 ${model} aco
    echo '-------------------<< Decompiling rewrite queries for Smallbank dataset (ACo) >>-------------------'
    $CMDADCo Decompile smallbank PostgreSQL 1 ${model} aco
    echo '-------------------<< Verifying rewrite queries for Smallbank dataset (ACo) >>-------------------'
    $CMDADCo Verify smallbank PostgreSQL 1 ${model} aco
}

if aco_pipeline; then
    echo '-------------------<< Running workload for Smallbank dataset (ACo) >>-------------------'
    $CMDRunWorkload smallbank PostgreSQL ${model} aco
else
    echo 'WARNING: ACo rewrite pipeline failed; skipping its workload measurement.' >&2
fi
