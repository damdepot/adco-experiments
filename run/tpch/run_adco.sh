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
bench_timer "tpch/run_adco" "results/tpch/adco" "adco"
cd "${ROOT}"

# clean original results
rm -rf results/tpch/adco
mkdir -p results/tpch/adco/benchmarks

rm -rf out/query_layer/ADCo-results
mkdir -p out/query_layer/ADCo-results

export iteration=2
export result_dir="results/tpch/adco"
export result_benchmark_path="results/tpch/adco/benchmarks"
export result_output_path="out/query_layer/ADCo-results"

CMDADCo=./scripts/common/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh
CMDDocker=./scripts/common/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### ADCo (Unified Rewrite + Tune)
### *****************************
adco_pipeline() {
    echo '-------------------<< Compiling TPCH dataset (ADCo) >>-------------------'
    $CMDADCo Compile tpch PostgreSQL 1 ${model} adco
    echo '-------------------<< Generating ADCo unified queries for TPCH dataset >>-------------------'
    $CMDADCo Rewrite tpch PostgreSQL 1 ${model} adco
    $CMDDocker Restart ${db_container}
    echo '-------------------<< Decompiling rewrite queries for TPCH dataset (ADCo) >>-------------------'
    $CMDADCo Decompile tpch PostgreSQL 1 ${model} adco
    echo '-------------------<< Verifying rewrite queries for TPCH dataset (ADCo) >>-------------------'
    $CMDADCo Verify tpch PostgreSQL 1 ${model} adco
}

if adco_pipeline; then
    echo '-------------------<< Running workload for TPCH dataset (ADCo) >>-------------------'
    $CMDRunWorkload tpch PostgreSQL ${model} adco
else
    echo 'WARNING: ADCo pipeline failed; skipping its workload measurement.' >&2
fi
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
