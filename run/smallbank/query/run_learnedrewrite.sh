#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

rm -rf results/query-smallbank/learnedrewrite
mkdir -p results/query-smallbank/learnedrewrite/benchmarks

rm -rf out/query_layer/LearnedRewrite-results
mkdir -p out/query_layer/LearnedRewrite-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-smallbank"
export result_dir="results/query-smallbank/learnedrewrite"
export result_benchmark_path="results/query-smallbank/learnedrewrite/benchmarks"
export result_output_path="out/query_layer/LearnedRewrite-results"

CMDLearnedRewrite=./scripts/common/query_layer/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running Smallbank LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite smallbank PostgreSQL

echo "-------------------<< Verifying LearnedRewrite rewrites for Smallbank dataset >>-------------------"
$CMDRunLRVerify smallbank PostgreSQL

echo "-------------------<< Running Workload for Smallbank dataset >>-------------------"
$CMDRunWorkload smallbank PostgreSQL LearnedRewrite
