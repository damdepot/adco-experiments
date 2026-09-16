#!/bin/bash

# clean original results
rm -rf results/db_layer/adco
mkdir -p results/db_layer/adco/benchmarks

rm -rf results/db_layer/dco
mkdir -p results/db_layer/dco/benchmarks

rm -rf out/db_layer/ADCo-results
mkdir -p out/db_layer/ADCo-results

rm -rf out/db_layer/DCo-results
mkdir -p out/db_layer/DCo-results

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


### DCo
### **********
echo '-------------------<< Running DCo for Smallbank >>-------------------'
$CMDADCo DCo ${model} postgres smallbank
$CMDDocker Restart ${db_container}
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank dco
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 
sleep 5s


echo '-------------------<< Running DCo for TPCC >>-------------------'
$CMDADCo DCo ${model} postgres tpcc
$CMDDocker Restart ${db_container}
echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc dco
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s


### ADCo
### **********
echo '-------------------<< Running ADCo for Smallbank >>-------------------'
$CMDADCo ADCo ${model} postgres smallbank
$CMDDocker Restart ${db_container}
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank adco
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service} 
sleep 5s

echo '-------------------<< Running ADCo for TPCC >>-------------------'
$CMDADCo ADCo ${model} postgres tpcc
$CMDDocker Restart ${db_container}
echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc adco
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}