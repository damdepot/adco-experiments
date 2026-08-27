#!/bin/bash

set -e

rm -rf results/db_layer/learnedrewrite
mkdir -p results/db_layer/learnedrewrite/benchmarks

rm -rf out/db_layer/LearnedRewrite-results
mkdir -p out/db_layer/LearnedRewrite-results

export iteration=5
export result_dir="results/db_layer/learnedrewrite"
export result_benchmark_path="results/db_layer/learnedrewrite/benchmarks"
export result_output_path="out/db_layer/LearnedRewrite-results"

CMDLearnedRewrite=./scripts/db_layer/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/db_layer/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/db_layer/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running Stats-Lite LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite stats-lite PostgreSQL

echo "-------------------<< Verifying LearnedRewrite rewrites for Stats-Lite dataset >>-------------------"
$CMDRunLRVerify stats-lite PostgreSQL

echo "-------------------<< Running Workload for Stats-Lite dataset >>-------------------"
$CMDRunWorkload stats-lite PostgreSQL LearnedRewrite
