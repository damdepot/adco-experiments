#!/bin/bash

# clean original results
rm -rf results/query_layer/adco
mkdir -p results/query_layer/adco/benchmarks

rm -rf out/query_layer/ADCo-results
mkdir -p out/query_layer/ADCo-results

export iteration=5
export result_dir="results/query_layer/adco"
export result_benchmark_path="results/query_layer/adco/benchmarks"
export result_output_path="out/query_layer/ADCo-results"

CMDADCo=./scripts/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

### Compile
#****************
echo '-------------------<< Compiling Stats-Lite dataset >>-------------------'
$CMDADCo Compile stats PostgreSQL 1 ${model}

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Rewrite stats PostgreSQL 1 ${model}

###  Decompile
### ***********
echo '-------------------<< Decompiling rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Decompile stats PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Verify stats PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for Stats-Lite dataset >>-------------------'
$CMDRunWorkload stats PostgreSQL ${model}
