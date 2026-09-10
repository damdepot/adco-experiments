#!/bin/bash

# clean baseline results
rm -rf results/db_layer/baseline
mkdir -p results/db_layer/baseline/benchmarks

export iteration=5

CMDRunSmallbank=./scripts/db_layer/exp1_Baselines/runExperiment1-Workload-Smallbank.sh
CMDRunTPCC=./scripts/db_layer/exp1_Baselines/runExperiment1-Workload-TPCC.sh


### Workload: Smallbank
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank postgres 100000 10000

### Workload: TPCC
### **********
echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC postgres 5 5
