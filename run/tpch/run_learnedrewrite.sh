#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_timer "tpch/run_learnedrewrite" "results/tpch/learnedrewrite" "learnedrewrite"

rm -rf results/tpch/learnedrewrite
mkdir -p results/tpch/learnedrewrite/benchmarks

rm -rf out/query_layer/LearnedRewrite-results
mkdir -p out/query_layer/LearnedRewrite-results

export iteration=2
export result_dir="results/tpch/learnedrewrite"
export result_benchmark_path="results/tpch/learnedrewrite/benchmarks"
export result_output_path="out/query_layer/LearnedRewrite-results"

CMDLearnedRewrite=./scripts/common/query_layer/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running TPCH LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite tpch PostgreSQL 1

echo "-------------------<< Verifying LearnedRewrite rewrites for TPCH dataset >>-------------------"
$CMDRunLRVerify tpch PostgreSQL

echo "-------------------<< Running Workload for TPCH dataset >>-------------------"
$CMDRunWorkload tpch PostgreSQL LearnedRewrite
