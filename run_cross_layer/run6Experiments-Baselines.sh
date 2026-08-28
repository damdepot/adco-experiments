#!/bin/bash

# clean baseline results
rm -rf results/cross_layer/baseline
mkdir -p results/cross_layer/baseline/benchmarks

export iteration=5
CMDBaseline=./scripts/cross_layer/exp1_Baselines/runExperiment1-Workload-Smallbank.sh

### Workload: Smallbank
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDBaseline postgres 1000 10000 smallbank
