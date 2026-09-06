#!/bin/bash

set -e

rm -rf results/query_layer/learnedrewrite
mkdir -p results/query_layer/learnedrewrite/benchmarks

rm -rf out/query_layer/LearnedRewrite-results
mkdir -p out/query_layer/LearnedRewrite-results

export iteration=5
export result_dir="results/query_layer/learnedrewrite"
export result_benchmark_path="results/query_layer/learnedrewrite/benchmarks"
export result_output_path="out/query_layer/LearnedRewrite-results"

CMDLearnedRewrite=./scripts/query_layer/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running Stats-Lite LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite stats PostgreSQL

echo "-------------------<< Verifying LearnedRewrite rewrites for Stats-Lite dataset >>-------------------"
$CMDRunLRVerify stats PostgreSQL

echo "-------------------<< Running Workload for Stats-Lite dataset >>-------------------"
$CMDRunWorkload stats PostgreSQL LearnedRewrite
