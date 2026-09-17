#!/bin/bash

# clean original results
rm -rf results/adco_only/aco
mkdir -p results/adco_only/aco/benchmarks

rm -rf out/adco_only/ACo-results
mkdir -p out/adco_only/ACo-results

CMDADCo=./scripts/adco_only/runExperiment0.sh
CMDRunSmallbank=./scripts/adco_only/runExperiment0-Workload-Smallbank.sh
CMDRunTPCC=./scripts/adco_only/runExperiment0-Workload-TPCC.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### ACo
### **********
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s
echo '-------------------<< ACo >>-------------------'
echo '-------------------<< Generating ACo rewrite for Smallbank >>-------------------'
$CMDADCo ACo ${model} postgres smallbank
echo '-------------------<< Running ACo Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank aco

echo '-------------------<< Generating ACo rewrite for TPCC >>-------------------'
$CMDADCo ACo ${model} postgres tpcc
echo '-------------------<< Running ACo TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc aco

echo '-------------------<< ACo completed >>-------------------'