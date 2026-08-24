#!/bin/bash

set -e

rm -rf results/learnedrewrite
mkdir -p results/learnedrewrite/benchmarks

rm -rf LearnedRewrite-results
mkdir -p LearnedRewrite-results

export iteration=5
export result_dir="results/learnedrewrite"
export result_benchmark_path="results/learnedrewrite/benchmarks"
export result_output_path="LearnedRewrite-results"

CMDLearnedRewrite=./scripts/exp2_Baselines/runExperiment2-LearnedRewrite.sh
CMDRunLRVerify=./scripts/exp2_Baselines/runExperiment2-Workload-Verify-LearnedRewrite.sh
CMDRunWorkload=./scripts/exp2_Baselines/runExperiment2-Workload.sh

echo "-------------------<< Running Stats-Lite LearnedRewrite rewrites >>-------------------"
$CMDLearnedRewrite stats-lite PostgreSQL

echo "-------------------<< Verifying LearnedRewrite rewrites for Stats-Lite dataset >>-------------------"
$CMDRunLRVerify stats-lite PostgreSQL

echo "-------------------<< Running Workload for Stats-Lite dataset >>-------------------"
$CMDRunWorkload stats-lite PostgreSQL LearnedRewrite
