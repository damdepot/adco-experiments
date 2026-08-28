#!/bin/bash

# clean original results
rm -rf results/cross_layer/py-dbridge
mkdir -p results/cross_layer/py-dbridge/benchmarks

rm -rf out/cross_layer/Py-DBridge-results
mkdir -p out/cross_layer/Py-DBridge-results

export iteration=5
export result_dir="results/cross_layer/py-dbridge"
export result_benchmark_path="results/cross_layer/py-dbridge/benchmarks"
export result_output_path="out/cross_layer/Py-DBridge-results"

CMDPyDBridge=./scripts/cross_layer/exp1_Baselines/runExperiment1-Py-DBridge.sh
CMDRunSmallbank=./scripts/cross_layer/exp1_Baselines/runExperiment1-Workload-Smallbank-Py-DBridge.sh

model="gemini-3.5-flash-lite"


###  Rewrite
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/smallbank"
source_file="drivers/postgresdriver.py"
$CMDPyDBridge ${workload_path} ${source_file} postgres smallbank

### Workload: Smallbank
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank postgres 1000 10000 smallbank
