#!/bin/bash

# clean original results
rm -rf results/query_layer/adco
mkdir -p results/query_layer/adco/benchmarks

rm -rf results/query_layer/aco
mkdir -p results/query_layer/aco/benchmarks

rm -rf out/query_layer/ADCo-results
mkdir -p out/query_layer/ADCo-results

rm -rf out/query_layer/ACo-results
mkdir -p out/query_layer/ACo-results

export iteration=5
export result_dir="results/query_layer/adco"
export result_benchmark_path="results/query_layer/adco/benchmarks"
export result_output_path="out/query_layer/ADCo-results"

CMDADCo=./scripts/query_layer/exp0_ADCo/runExperiment0.sh
CMDRunWorkload=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload.sh
CMDDocker=./scripts/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"
db_service="pgdb"


### ACo (Rewrite-only)
### ******************
echo '-------------------<< Compiling Stats-Lite dataset (ACo) >>-------------------'
$CMDADCo Compile stats PostgreSQL 1 ${model} aco
echo '-------------------<< Generating ACo rewrite queries for Stats-Lite dataset >>-------------------'
$CMDADCo Rewrite stats PostgreSQL 1 ${model} aco
echo '-------------------<< Decompiling rewrite queries for Stats-Lite dataset (ACo) >>-------------------'
$CMDADCo Decompile stats PostgreSQL 1 ${model} aco
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset (ACo) >>-------------------'
$CMDADCo Verify stats PostgreSQL 1 ${model} aco
echo '-------------------<< Running workload for Stats-Lite dataset (ACo) >>-------------------'
$CMDRunWorkload stats PostgreSQL ${model} aco


### ADCo (Unified Rewrite + Tune)
### *****************************
echo '-------------------<< Compiling Stats-Lite dataset (ADCo) >>-------------------'
$CMDADCo Compile stats PostgreSQL 1 ${model} adco
echo '-------------------<< Generating ADCo unified queries for Stats-Lite dataset >>-------------------'
$CMDADCo Rewrite stats PostgreSQL 1 ${model} adco
$CMDDocker Restart ${db_container}
echo '-------------------<< Decompiling rewrite queries for Stats-Lite dataset (ADCo) >>-------------------'
$CMDADCo Decompile stats PostgreSQL 1 ${model} adco
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset (ADCo) >>-------------------'
$CMDADCo Verify stats PostgreSQL 1 ${model} adco
echo '-------------------<< Running workload for Stats-Lite dataset (ADCo) >>-------------------'
$CMDRunWorkload stats PostgreSQL ${model} adco
$CMDDocker Down ${db_container}
$CMDDocker Up ${db_container} ${db_service}
