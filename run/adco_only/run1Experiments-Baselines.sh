#!/bin/bash

# clean baseline results
rm -rf results/adco_only/baseline
mkdir -p results/adco_only/baseline/benchmarks

export iteration=5
CMDRunSmallbank=./scripts/adco_only/runExperiment1-Workload-Smallbank.sh
CMDRunTPCC=./scripts/adco_only/runExperiment1-Workload-TPCC.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh
db_container="adcoexp-db"
db_service="pgdb"

### Workload: Smallbank
### **********
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s
echo '-------------------<< Running the Smallbank workload >>-------------------'
$CMDRunSmallbank postgres 100000 10000
echo '-------------------<< Running the TPCC workload >>-------------------'
$CMDRunTPCC postgres 5 5
