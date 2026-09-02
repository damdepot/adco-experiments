#!/bin/bash

# clean baseline results
rm -rf results/query_layer/baseline
mkdir -p results/query_layer/baseline/benchmarks

export iteration=5
CMDBaseline=./scripts/query_layer/exp2_Baselines/runExperiment2-Baseline.sh

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for Stats-Lite dataset >>-------------------'
$CMDBaseline stats PostgreSQL 1