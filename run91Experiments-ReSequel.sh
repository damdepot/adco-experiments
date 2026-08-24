#!/bin/bash

# clean original results
rm -rf results/resequel
mkdir -p results/resequel/benchmarks

rm -rf ReSequel-results
mkdir -p ReSequel-results

export iteration=5
export result_dir="results/resequel"
export result_benchmark_path="results/resequel/benchmarks"
export result_output_path="ReSequel-results"

CMDReSequel=./scripts/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

## Build Catalog
#***************
echo '-------------------<< Building Catalog for Stats-Lite dataset >>-------------------'
$CMDReSequel BuildCatalog stats-lite PostgreSQL 1

## Templatization
#****************
echo '-------------------<< Templatizing Stats-Lite dataset >>-------------------'
$CMDReSequel Templatization stats-lite PostgreSQL 1

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Generate stats-lite PostgreSQL 1 ${model}

###  Reconstruct
### ***********
echo '-------------------<< Reconstructing rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Reconstruct stats-lite PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for Stats-Lite dataset >>-------------------'
$CMDReSequel Verify stats-lite PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for Stats-Lite dataset >>-------------------'
$CMDRunWorkload stats-lite PostgreSQL ${model}