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
CMDRunSmallbank=./scripts/db_layer/exp0_ADCo/runExperiment0-Workload-Smallbank-ADCo.sh
CMDRunTPCC=./scripts/db_layer/exp0_ADCo/runExperiment0-Workload-TPCC-ADCo.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### Smallbank
### **********
echo '-------------------<< Tuning knobs for Smallbank >>-------------------'
$CMDADCo KnobTune ${model} postgres smallbank
$CMDDocker Restart ${db_container}

echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 50000 10000 smallbank

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 
sleep 5s

### TPCC
### **********
echo '-------------------<< Tuning knobs for TPCC >>-------------------'
$CMDADCo KnobTune ${model} postgres tpcc
$CMDDocker Restart ${db_container}

echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 1 1 tpcc

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 