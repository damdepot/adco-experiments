#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

# clean original results
rm -rf results/query-tpcc/resequel
mkdir -p results/query-tpcc/resequel/benchmarks

rm -rf out/query_layer/ReSequel-results
mkdir -p out/query_layer/ReSequel-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-tpcc"
export result_dir="results/query-tpcc/resequel"
export result_benchmark_path="results/query-tpcc/resequel/benchmarks"
export result_output_path="out/query_layer/ReSequel-results"

CMDReSequel=./scripts/common/query_layer/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

## Build Catalog
#***************
echo '-------------------<< Building Catalog for TPCC dataset >>-------------------'
$CMDReSequel BuildCatalog tpcc PostgreSQL 1

## Templatization
#****************
echo '-------------------<< Templatizing TPCC dataset >>-------------------'
$CMDReSequel Templatization tpcc PostgreSQL 1

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for TPCC dataset >>-------------------'
$CMDReSequel Generate tpcc PostgreSQL 1 ${model}

###  Reconstruct
### ***********
echo '-------------------<< Reconstructing rewrite queries for TPCC dataset >>-------------------'
$CMDReSequel Reconstruct tpcc PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for TPCC dataset >>-------------------'
$CMDReSequel Verify tpcc PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for TPCC dataset >>-------------------'
$CMDRunWorkload tpcc PostgreSQL ${model}
