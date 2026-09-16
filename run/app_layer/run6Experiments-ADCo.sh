#!/bin/bash

# Clean results and output directories
rm -rf results/app_layer/adco results/app_layer/aco
mkdir -p results/app_layer/adco/benchmarks results/app_layer/aco/benchmarks
rm -rf out/app_layer/ADCo-results out/app_layer/ACo-results
mkdir -p out/app_layer/ADCo-results out/app_layer/ACo-results

# Define variables and command paths
CMDADCo=./scripts/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbank=./scripts/app_layer/exp0_ADCo/runExperiment0-Workload-Smallbank-ADCo.sh
CMDRunTPCC=./scripts/app_layer/exp0_ADCo/runExperiment0-Workload-TPCC-ADCo.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"

### ACo
### **********
echo '-------------------<< ACo >>-------------------'
echo '-------------------<< Generating ACo rewrite for Smallbank >>-------------------'
$CMDADCo ACo ${model} postgres smallbank
echo '-------------------<< Running ACo Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank aco

echo '-------------------<< Generating ACo rewrite for TPCC >>-------------------'
$CMDADCo ACo ${model} postgres tpcc
echo '-------------------<< Running ACo TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc aco


### ADCo
### **********
echo '-------------------<< ADCo >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for Smallbank >>-------------------'
$CMDADCo ADCo ${model} postgres smallbank
$CMDDocker Restart ${db_container}
echo '-------------------<< Running ADCo Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank adco
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s

echo '-------------------<< Generating ADCo (ACo + DCo) for TPCC >>-------------------'
$CMDADCo ADCo ${model} postgres tpcc
$CMDDocker Restart ${db_container}
echo '-------------------<< Running ADCo TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc adco
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
