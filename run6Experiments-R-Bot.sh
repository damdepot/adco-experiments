#!/bin/bash

set -e

rm -rf results/r-bot
mkdir -p results/r-bot

CMDBaselineRBot=./explocal/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./explocal/exp2_Baselines/runExperiment2-Verify-R-Bot.sh
CMDRunWorkload=./explocal/exp2_Baselines/runExperiment2-Workload.sh

model=gemini-3.5-flash-lite

### Rewrite Stats with R-Bot
#**************************
echo "-------------------<< Running Stats-Lite R-Bot rewrites >>-------------------"
$CMDBaselineRBot stats-lite PostgreSQL R-Bot ${llm_model}

### Verify Stats R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for Stats-Lite dataset >>-------------------"
$CMDRunRBotVerify stats-lite PostgreSQL ${llm_model}

### Run Stats R-Bot workload
#**************************
echo "-------------------<< Running Stats-Lite R-Bot workload >>-------------------"
$CMDRunWorkload stats-lite PostgreSQL R-Bot-Gemini
