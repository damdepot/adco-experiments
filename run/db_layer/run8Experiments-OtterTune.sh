#!/bin/bash

# clean original results
rm -rf results/db_layer/ottertune
mkdir -p results/db_layer/ottertune/benchmarks

export iteration=5
export result_dir="results/db_layer/ottertune"
export result_benchmark_path="results/db_layer/ottertune/benchmarks"

CMDOtterTune=./scripts/db_layer/exp1_Baselines/runExperiment1-OtterTune.sh
CMDRunSmallbank=./scripts/db_layer/exp1_Baselines/runExperiment0-Workload-Smallbank-OtterTune.sh
CMDRunTPCC=./scripts/db_layer/exp1_Baselines/runExperiment0-Workload-TPCC-OtterTune.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

db_container="adcoexp-db"
db_service="pgdb"


### Smallbank
### **********
echo '-------------------<< Tuning knobs with OtterTune for Smallbank >>-------------------'
$CMDOtterTune postgres smallbank

echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank postgres 100000 10000 smallbank

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 
sleep 5s

### TPCC
### **********
echo '-------------------<< Tuning knobs with OtterTune for TPCC >>-------------------'
$CMDOtterTune postgres tpcc

echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC postgres 5 5 tpcc

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
