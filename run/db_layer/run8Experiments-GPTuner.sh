#!/bin/bash

# clean original results
rm -rf results/db_layer/gptuner
mkdir -p results/db_layer/gptuner/benchmarks

rm -rf out/db_layer/GPTuner-results
mkdir -p out/db_layer/GPTuner-results

export iteration=5
export result_dir="results/db_layer/gptuner"
export result_benchmark_path="results/db_layer/gptuner/benchmarks"
export result_output_path="out/db_layer/GPTuner-results"

CMDGPTuner=./scripts/db_layer/exp1_Baselines/runExperiment1-GPTuner.sh
CMDRunSmallbank=./scripts/db_layer/exp1_Baselines/runExperiment0-Workload-Smallbank-GPTuner.sh
CMDRunTPCC=./scripts/db_layer/exp1_Baselines/runExperiment0-Workload-TPCC-GPTuner.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### Smallbank
### **********
echo '-------------------<< Tuning knobs with GPTuner for Smallbank >>-------------------'
$CMDGPTuner postgres smallbank

echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 
sleep 5s

### TPCC
### **********
echo '-------------------<< Tuning knobs with GPTuner for TPCC >>-------------------'
$CMDGPTuner postgres tpcc

echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
