#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"

# clean original results
rm -rf results/query-smallbank/resequel
mkdir -p results/query-smallbank/resequel/benchmarks

rm -rf out/query_layer/ReSequel-results
mkdir -p out/query_layer/ReSequel-results

export iteration=2
export RESULTS_DATASET_DIR="results/query-smallbank"
export result_dir="results/query-smallbank/resequel"
export result_benchmark_path="results/query-smallbank/resequel/benchmarks"
export result_output_path="out/query_layer/ReSequel-results"

CMDReSequel=./scripts/common/query_layer/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

## Build Catalog
#***************
echo '-------------------<< Building Catalog for Smallbank dataset >>-------------------'
$CMDReSequel BuildCatalog smallbank PostgreSQL 1

## Templatization
#****************
echo '-------------------<< Templatizing Smallbank dataset >>-------------------'
$CMDReSequel Templatization smallbank PostgreSQL 1

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for Smallbank dataset >>-------------------'
$CMDReSequel Generate smallbank PostgreSQL 1 ${model}

###  Reconstruct
### ***********
echo '-------------------<< Reconstructing rewrite queries for Smallbank dataset >>-------------------'
$CMDReSequel Reconstruct smallbank PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for Smallbank dataset >>-------------------'
$CMDReSequel Verify smallbank PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for Smallbank dataset >>-------------------'
$CMDRunWorkload smallbank PostgreSQL ${model}
