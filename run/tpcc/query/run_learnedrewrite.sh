#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

rm -rf results/query-tpcc/learnedrewrite
mkdir -p results/query-tpcc/learnedrewrite/benchmarks

rm -rf out/query_layer/LearnedRewrite-results
mkdir -p out/query_layer/LearnedRewrite-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-tpcc"
export result_dir="results/query-tpcc/learnedrewrite"
export result_benchmark_path="results/query-tpcc/learnedrewrite/benchmarks"
export result_output_path="out/query_layer/LearnedRewrite-results"

CMDLearnedRewrite=./scripts/common/query_layer/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running TPCC LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite tpcc PostgreSQL

echo "-------------------<< Verifying LearnedRewrite rewrites for TPCC dataset >>-------------------"
$CMDRunLRVerify tpcc PostgreSQL

echo "-------------------<< Running Workload for TPCC dataset >>-------------------"
$CMDRunWorkload tpcc PostgreSQL LearnedRewrite
