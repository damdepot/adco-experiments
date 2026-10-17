#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "stats/run_adco" "results/stats/adco" "adco"
cd "${ROOT}"
bench_snapshot_seed stats stats_seed ./run/setup/stats-prepare-postgres-remote.sh

# clean original results
rm -rf results/stats/adco
mkdir -p results/stats/adco/benchmarks

rm -rf out/query_layer/ADCo-results
mkdir -p out/query_layer/ADCo-results

export iteration=2
export result_dir="results/stats/adco"
export result_benchmark_path="results/stats/adco/benchmarks"
export result_output_path="out/query_layer/ADCo-results"

CMDADCo=./scripts/common/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh
CMDDocker=./scripts/common/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"


### ADCo (Unified Rewrite + Tune)
### *****************************
adco_pipeline() {
    echo '-------------------<< Compiling Stats-Lite dataset (ADCo) >>-------------------'
    $CMDADCo Compile stats PostgreSQL 1 ${model} adco
    echo '-------------------<< Generating ADCo unified queries for Stats-Lite dataset >>-------------------'
    python3 "${ROOT}/tools/check_knobs.py" || return 1
    $CMDADCo Rewrite stats PostgreSQL 1 ${model} adco || return 1
    python3 "${ROOT}/tools/check_knobs.py" || return 1
    $CMDDocker Restart ${db_container}
    echo '-------------------<< Decompiling rewrite queries for Stats-Lite dataset (ADCo) >>-------------------'
    $CMDADCo Decompile stats PostgreSQL 1 ${model} adco
    echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset (ADCo) >>-------------------'
    $CMDADCo Verify stats PostgreSQL 1 ${model} adco
}

bench_fresh_db stats stats_seed users "${STATS_USERS_ROWS:-40325}"
if adco_pipeline; then
    echo '-------------------<< Running workload for Stats-Lite dataset (ADCo) >>-------------------'
    $CMDRunWorkload stats PostgreSQL ${model} adco
else
    echo 'WARNING: ADCo pipeline failed; skipping its workload measurement.' >&2
fi
$CMDDocker Restart ${db_container}
$CMDDocker WaitFor ${db_container}
