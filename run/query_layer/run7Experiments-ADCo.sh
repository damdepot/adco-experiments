#!/bin/bash

# clean original results
rm -rf results/db_layer/adco
mkdir -p results/db_layer/adco/benchmarks

rm -rf out/db_layer/ADCo-results
mkdir -p out/db_layer/ADCo-results

export iteration=5
export result_dir="results/db_layer/adco"
export result_benchmark_path="results/db_layer/adco/benchmarks"
export result_output_path="out/db_layer/ADCo-results"

CMDADCo=./scripts/db_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/db_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

### Compile
#****************
echo '-------------------<< Compiling Stats-Lite dataset >>-------------------'
$CMDADCo Compile stats-lite PostgreSQL 1 ${model}

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Rewrite stats-lite PostgreSQL 1 ${model}

###  Decompile
### ***********
echo '-------------------<< Decompiling rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Decompile stats-lite PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Verify stats-lite PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for Stats-Lite dataset >>-------------------'
$CMDRunWorkload stats-lite PostgreSQL ${model}
