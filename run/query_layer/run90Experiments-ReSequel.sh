#!/bin/bash

# clean original results
rm -rf results/query_layer/resequel
mkdir -p results/query_layer/resequel/benchmarks

rm -rf out/query_layer/ReSequel-results
mkdir -p out/query_layer/ReSequel-results

export iteration=5
export result_dir="results/query_layer/resequel"
export result_benchmark_path="results/query_layer/resequel/benchmarks"
export result_output_path="out/query_layer/ReSequel-results"

CMDReSequel=./scripts/query_layer/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

## Build Catalog
#***************
echo '-------------------<< Building Catalog for Stats-Lite dataset >>-------------------'
$CMDReSequel BuildCatalog stats PostgreSQL 1

## Templatization
#****************
echo '-------------------<< Templatizing Stats-Lite dataset >>-------------------'
$CMDReSequel Templatization stats PostgreSQL 1

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Generate stats PostgreSQL 1 ${model}

###  Reconstruct
### ***********
echo '-------------------<< Reconstructing rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Reconstruct stats PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Verify stats PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for Stats-Lite dataset >>-------------------'
$CMDRunWorkload stats PostgreSQL ${model}