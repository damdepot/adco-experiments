#!/bin/bash
set -euo pipefail

# clean original results
rm -rf results/adco_only/dco
mkdir -p results/adco_only/dco/benchmarks

rm -rf out/adco_only/DCo-results
mkdir -p out/adco_only/DCo-results

CMDADCo=./scripts/adco_only/runExperiment0.sh
CMDRunSmallbank=./scripts/adco_only/runExperiment0-Workload-Smallbank.sh
CMDRunTPCC=./scripts/adco_only/runExperiment0-Workload-TPCC.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### DCo
### **********
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s
echo '-------------------<< DCo >>-------------------'
echo '-------------------<< Running DCo for Smallbank >>-------------------'
$CMDADCo DCo ${model} postgres smallbank
$CMDDocker Restart ${db_container}
sleep 3s
echo "Verifying active PostgreSQL shared_buffers on ${db_container}..."
docker exec "${db_container}" psql -U postgres -c "SHOW shared_buffers;"
echo '-------------------<< Running DCo Smallbank workload >>-------------------'
$CMDRunSmallbank ${model} postgres 100000 10000 smallbank dco
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s

echo '-------------------<< Running DCo for TPCC >>-------------------'
$CMDADCo DCo ${model} postgres tpcc
$CMDDocker Restart ${db_container}
sleep 3s
echo "Verifying active PostgreSQL shared_buffers on ${db_container}..."
docker exec "${db_container}" psql -U postgres -c "SHOW shared_buffers;"
echo '-------------------<< Running DCo TPCC workload >>-------------------'
$CMDRunTPCC ${model} postgres 5 5 tpcc dco
echo '-------------------<< Refreshing docker production database >>-------------------'
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
sleep 5s

echo '-------------------<< DCo completes >>-------------------'