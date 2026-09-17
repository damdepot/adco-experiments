#!/bin/bash

set -e

rm -rf results/query_layer/r-bot
mkdir -p results/query_layer/r-bot/benchmarks

rm -rf out/query_layer/R-Bot-results
mkdir -p out/query_layer/R-Bot-results

export iteration=5
export result_dir="results/query_layer/r-bot"
export result_benchmark_path="results/query_layer/r-bot/benchmarks"
export result_output_path="out/query_layer/R-Bot-results"

CMDBaselineRBot=./scripts/query_layer/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-R-Bot.sh
CMDRunWorkload=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model=gemini-3.5-flash-lite

### Rewrite Stats with R-Bot
#**************************
echo "-------------------<< Running Stats-Lite R-Bot rewrites >>-------------------"
$CMDBaselineRBot stats PostgreSQL R-Bot ${model}

### Verify Stats R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for Stats-Lite dataset >>-------------------"
$CMDRunRBotVerify stats PostgreSQL ${model}

### Run Stats R-Bot workload
#**************************
echo "-------------------<< Running Stats-Lite R-Bot workload >>-------------------"
$CMDRunWorkload stats PostgreSQL ${model}
