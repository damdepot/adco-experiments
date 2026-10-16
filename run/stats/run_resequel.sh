#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_lock "${ROOT}"
bench_timer "stats/run_resequel" "results/stats/resequel" "resequel"
bench_snapshot_seed stats stats_seed ./run/setup/stats-prepare-postgres-remote.sh

# clean original results
rm -rf results/stats/resequel
mkdir -p results/stats/resequel/benchmarks

rm -rf out/query_layer/ReSequel-results
mkdir -p out/query_layer/ReSequel-results

export iteration=2
export result_dir="results/stats/resequel"
export result_benchmark_path="results/stats/resequel/benchmarks"
export result_output_path="out/query_layer/ReSequel-results"

CMDReSequel=./scripts/common/query_layer/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

## Templatization
#****************
echo '-------------------<< Templatizing Stats-Lite dataset >>-------------------'
$CMDReSequel Templatization stats PostgreSQL 1

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Generate stats PostgreSQL 1 ${model}

###  Reconstruct
### ***********
echo '-------------------<< Reconstructing rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Reconstruct stats PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Verify stats PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for Stats-Lite dataset >>-------------------'
bench_fresh_db stats stats_seed users "${STATS_USERS_ROWS:-40325}"
python3 "${ROOT}/tools/check_knobs.py"
$CMDRunWorkload stats PostgreSQL ${model}
