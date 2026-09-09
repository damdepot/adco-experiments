#!/bin/bash

# clean original results
rm -rf results/db_layer/agenttune
mkdir -p results/db_layer/agenttune/benchmarks

rm -rf out/db_layer/AgentTune-results
mkdir -p out/db_layer/AgentTune-results

export iteration=5
export result_dir="results/db_layer/agenttune"
export result_benchmark_path="results/db_layer/agenttune/benchmarks"
export result_output_path="out/db_layer/AgentTune-results"

CMDAgentTune=./scripts/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh
CMDRunSmallbank=./scripts/db_layer/exp1_Baselines/runExperiment0-Workload-Smallbank-AgentTune.sh
CMDRunTPCC=./scripts/db_layer/exp1_Baselines/runExperiment0-Workload-TPCC-AgentTune.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### Smallbank
### **********
echo '-------------------<< Tuning knobs for Smallbank >>-------------------'
$CMDAgentTune postgres smallbank

echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 50000 10000 smallbank

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 
sleep 5s

### TPCC
### **********
echo '-------------------<< Tuning knobs for TPCC >>-------------------'
$CMDAgentTune postgres tpcc

echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 1 1 tpcc

echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}