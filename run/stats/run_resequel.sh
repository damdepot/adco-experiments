#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

# clean original results
rm -rf results/stats/resequel
mkdir -p results/stats/resequel/benchmarks

rm -rf out/query_layer/ReSequel-results
mkdir -p out/query_layer/ReSequel-results

export iteration=5
export result_dir="results/stats/resequel"
export result_benchmark_path="results/stats/resequel/benchmarks"
export result_output_path="out/query_layer/ReSequel-results"

CMDReSequel=./scripts/stats/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/stats/exp2_Baselines/runExperiment2-Workload.sh

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