#!/bin/bash

# clean baseline results
rm -rf results/db_layer/baseline
mkdir -p results/db_layer/baseline/benchmarks

export iteration=5
CMDBaseline=./scripts/db_layer/exp2_Baselines/runExperiment2-Baseline.sh

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for Stats-Lite dataset >>-------------------'
$CMDBaseline stats-lite PostgreSQL 1