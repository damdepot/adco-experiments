#!/bin/bash

# clean original results
rm -rf results/cross_layer/adco
mkdir -p results/cross_layer/adco/benchmarks

rm -rf out/cross_layer/ADCo-results
mkdir -p out/cross_layer/ADCo-results

export iteration=5
export result_dir="results/cross_layer/adco"
export result_benchmark_path="results/cross_layer/adco/benchmarks"
export result_output_path="out/cross_layer/ADCo-results"

CMDADCo=./scripts/cross_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbank=./scripts/cross_layer/exp0_ADCo/runExperiment0-Workload-Smallbank-ADCo.sh
CMDLoadSmallbank=./scripts/cross_layer/exp1_Baselines/runExperiment1-Workload-Smallbank-Load.sh

model="gemini-3.5-flash-lite"


###  Rewrite
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
$CMDADCo Rewrite ${model} postgres smallbank

### Workload: Smallbank
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDLoadSmallbank postgres 1000
$CMDRunSmallbank ${model} postgres 1000 10000 smallbank
