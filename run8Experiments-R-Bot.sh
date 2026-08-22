#!/bin/bash

set -e

rm -rf results/r-bot
mkdir -p results/r-bot

rm -rf R-Bot-results
mkdir -p R-Bot-results

export iteration=5
export result_dir="results/r-bot"
export result_output_path="R-Bot-results"

CMDBaselineRBot=./explocal/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./explocal/exp2_Baselines/runExperiment2-Workload-Verify-R-Bot.sh
CMDRunWorkload=./explocal/exp2_Baselines/runExperiment2-Workload.sh

model=gemini-3.5-flash-lite

### Rewrite Stats with R-Bot
#**************************
echo "-------------------<< Running Stats-Lite R-Bot rewrites >>-------------------"
$CMDBaselineRBot stats-lite PostgreSQL R-Bot ${model}

### Verify Stats R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for Stats-Lite dataset >>-------------------"
$CMDRunRBotVerify stats-lite PostgreSQL ${model}

### Run Stats R-Bot workload
#**************************
echo "-------------------<< Running Stats-Lite R-Bot workload >>-------------------"
$CMDRunWorkload stats-lite PostgreSQL ${model}
