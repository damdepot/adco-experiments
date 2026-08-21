#!/bin/bash

set -e

cd "$(dirname "$0")"

mkdir -p setup/Baselines
ln -sfn "../../baselines/R-Bot" setup/Baselines/R-Bot
ln -sfn "../../workload_runner" setup/Baselines/Workload

if [ ! -x workload/venv/bin/python ]; then
    uv venv workload/venv --system-site-packages
fi

rm -rf results/*
mkdir -p results

CMDBaselineRBot=./explocal/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./explocal/exp2_Baselines/runExperiment2-Verify-R-Bot.sh
CMDRunQueries=./explocal/exp2_Baselines/runExperiment2-ReSequel.sh

llm_model=gemini-3.5-flash-lite

### Rewrite Stats with R-Bot
echo "Running R-Bot rewrite for Stats dataset with LLM model: ${llm_model}"
"${CMDBaselineRBot}" stats-lite PostgreSQL R-Bot "${llm_model}"

### Verify Stats R-Bot rewrites
echo "Verifying R-Bot rewrites for Stats dataset with LLM model: ${llm_model}"
"${CMDRunRBotVerify}" stats-lite PostgreSQL "${llm_model}"

### Run Stats R-Bot rewrites
echo "Running Stats R-Bot rewrites for Stats dataset"
"${CMDRunQueries}" stats-lite PostgreSQL R-Bot-Gemini
