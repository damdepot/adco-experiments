#!/bin/bash

# clean original results
rm -rf results/app_layer/py-dbridge
mkdir -p results/app_layer/py-dbridge/benchmarks

rm -rf out/app_layer/Py-DBridge-results
mkdir -p out/app_layer/Py-DBridge-results

export iteration=5
export result_dir="results/app_layer/py-dbridge"
export result_benchmark_path="results/app_layer/py-dbridge/benchmarks"
export result_output_path="out/app_layer/Py-DBridge-results"

CMDPyDBridge=./scripts/app_layer/exp1_Baselines/runExperiment1-Py-DBridge.sh
CMDRunSmallbank=./scripts/app_layer/exp1_Baselines/runExperiment1-Workload-Smallbank-Py-DBridge.sh
CMDRunTPCC=./scripts/app_layer/exp1_Baselines/runExperiment1-Workload-TPCC-Py-DBridge.sh


###  Rewrite
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/smallbank"
source_file="drivers/postgresdriver.py"
$CMDPyDBridge ${workload_path} ${source_file} postgres smallbank

workload_path="workload/apps/tpcc"
source_file="drivers/postgresdriver.py"
$CMDPyDBridge ${workload_path} ${source_file} postgres tpcc

### Workload: Smallbank
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank postgres 50000 10000 smallbank

echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC postgres 1 1 tpcc
