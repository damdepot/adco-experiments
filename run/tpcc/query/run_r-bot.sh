#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

rm -rf results/query-tpcc/r-bot
mkdir -p results/query-tpcc/r-bot/benchmarks

rm -rf out/query_layer/R-Bot-results
mkdir -p out/query_layer/R-Bot-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-tpcc"
export result_dir="results/query-tpcc/r-bot"
export result_benchmark_path="results/query-tpcc/r-bot/benchmarks"
export result_output_path="out/query_layer/R-Bot-results"

CMDBaselineRBot=./scripts/common/query_layer/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-R-Bot.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

### Rewrite TPCC with R-Bot
#**************************
echo "-------------------<< Running TPCC R-Bot rewrites >>-------------------"
$CMDBaselineRBot tpcc PostgreSQL R-Bot ${model}

### Verify TPCC R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for TPCC dataset >>-------------------"
$CMDRunRBotVerify tpcc PostgreSQL ${model}

### Run TPCC R-Bot workload
#**************************
echo "-------------------<< Running TPCC R-Bot workload >>-------------------"
$CMDRunWorkload tpcc PostgreSQL ${model}
