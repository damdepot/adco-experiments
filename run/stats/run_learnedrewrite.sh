#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_lock "${ROOT}"
bench_timer "stats/run_learnedrewrite" "results/stats/learnedrewrite" "learnedrewrite"
bench_snapshot_seed stats stats_seed ./run/setup/stats-prepare-postgres-remote.sh

rm -rf results/stats/learnedrewrite
mkdir -p results/stats/learnedrewrite/benchmarks

rm -rf out/query_layer/LearnedRewrite-results
mkdir -p out/query_layer/LearnedRewrite-results

export iteration=2
export result_dir="results/stats/learnedrewrite"
export result_benchmark_path="results/stats/learnedrewrite/benchmarks"
export result_output_path="out/query_layer/LearnedRewrite-results"

CMDLearnedRewrite=./scripts/common/query_layer/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running Stats-Lite LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite stats PostgreSQL

echo "-------------------<< Verifying LearnedRewrite rewrites for Stats-Lite dataset >>-------------------"
$CMDRunLRVerify stats PostgreSQL

echo "-------------------<< Running Workload for Stats-Lite dataset >>-------------------"
bench_fresh_db stats stats_seed users "${STATS_USERS_ROWS:-40325}"
python3 "${ROOT}/tools/check_knobs.py"
$CMDRunWorkload stats PostgreSQL LearnedRewrite
