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
bench_timer "tpch/run_aco" "results/tpch/aco" "aco"
cd "${ROOT}"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

# clean original results
rm -rf results/tpch/aco
mkdir -p results/tpch/aco/benchmarks

rm -rf out/query_layer/ACo-results
mkdir -p out/query_layer/ACo-results

export iteration=2
export result_dir="results/tpch/aco"
export result_benchmark_path="results/tpch/aco/benchmarks"
export result_output_path="out/query_layer/ACo-results"

CMDADCo=./scripts/common/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"


### ACo (Rewrite-only)
### ******************
aco_pipeline() {
    echo '-------------------<< Compiling TPCH dataset (ACo) >>-------------------'
    $CMDADCo Compile tpch PostgreSQL 1 ${model} aco
    echo '-------------------<< Generating ACo rewrite queries for TPCH dataset >>-------------------'
    $CMDADCo Rewrite tpch PostgreSQL 1 ${model} aco
    echo '-------------------<< Decompiling rewrite queries for TPCH dataset (ACo) >>-------------------'
    $CMDADCo Decompile tpch PostgreSQL 1 ${model} aco
    echo '-------------------<< Verifying rewrite queries for TPCH dataset (ACo) >>-------------------'
    $CMDADCo Verify tpch PostgreSQL 1 ${model} aco
}

if aco_pipeline; then
    echo '-------------------<< Running workload for TPCH dataset (ACo) >>-------------------'
    bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
    python3 "${ROOT}/tools/check_knobs.py"
    $CMDRunWorkload tpch PostgreSQL ${model} aco
else
    echo 'WARNING: ACo rewrite pipeline failed; skipping its workload measurement.' >&2
fi
