#!/bin/bash

# clean original results
rm -rf results/adco_only/adco
mkdir -p results/adco_only/adco/benchmarks

rm -rf out/adco_only/ADCo-results
mkdir -p out/adco_only/ADCo-results

CMDADCo=./scripts/adco_only/runExperiment0.sh
CMDRunSmallbank=./scripts/adco_only/runExperiment0-Workload-Smallbank.sh
CMDRunTPCC=./scripts/adco_only/runExperiment0-Workload-TPCC.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### ADCo
### **********
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s
echo '-------------------<< ADCo >>-------------------'
echo '-------------------<< Generating ADCo for Smallbank >>-------------------'
$CMDADCo ADCo ${model} postgres smallbank
$CMDDocker Restart ${db_container}
sleep 3s
echo '-------------------<< Running ADCo Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank adco
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s

echo '-------------------<< Generating ADCo for TPCC >>-------------------'
$CMDADCo ADCo ${model} postgres tpcc
$CMDDocker Restart ${db_container}
sleep 3s
echo '-------------------<< Running ADCo TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc adco
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s

echo '-------------------<< ADCo completes >>-------------------'