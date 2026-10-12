#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

rm -rf results/query-smallbank/r-bot
mkdir -p results/query-smallbank/r-bot/benchmarks

rm -rf out/query_layer/R-Bot-results
mkdir -p out/query_layer/R-Bot-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-smallbank"
export result_dir="results/query-smallbank/r-bot"
export result_benchmark_path="results/query-smallbank/r-bot/benchmarks"
export result_output_path="out/query_layer/R-Bot-results"

CMDBaselineRBot=./scripts/common/query_layer/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-R-Bot.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

### Rewrite Smallbank with R-Bot
#**************************
echo "-------------------<< Running Smallbank R-Bot rewrites >>-------------------"
$CMDBaselineRBot smallbank PostgreSQL R-Bot ${model}

### Verify Smallbank R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for Smallbank dataset >>-------------------"
$CMDRunRBotVerify smallbank PostgreSQL ${model}

### Run Smallbank R-Bot workload
#**************************
echo "-------------------<< Running Smallbank R-Bot workload >>-------------------"
$CMDRunWorkload smallbank PostgreSQL ${model}
