#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_timer "tpch/run_resequel" "results/tpch/resequel" "resequel"

# clean original results
rm -rf results/tpch/resequel
mkdir -p results/tpch/resequel/benchmarks

rm -rf out/query_layer/ReSequel-results
mkdir -p out/query_layer/ReSequel-results

export iteration=2
export result_dir="results/tpch/resequel"
export result_benchmark_path="results/tpch/resequel/benchmarks"
export result_output_path="out/query_layer/ReSequel-results"

CMDReSequel=./scripts/common/query_layer/exp1_ReSequel/runExperiment1.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

## Build Catalog
#***************
echo '-------------------<< Building Catalog for TPCH dataset >>-------------------'
$CMDReSequel BuildCatalog tpch PostgreSQL 1

## Templatization
#****************
echo '-------------------<< Templatizing TPCH dataset >>-------------------'
$CMDReSequel Templatization tpch PostgreSQL 1

###  Rewrite
### **********
echo '-------------------<< Generating rewrite queries for TPCH dataset >>-------------------'
$CMDReSequel Generate tpch PostgreSQL 1 ${model}

###  Reconstruct
### ***********
echo '-------------------<< Reconstructing rewrite queries for TPCH dataset >>-------------------'
$CMDReSequel Reconstruct tpch PostgreSQL 1 ${model}

###  Verify
### *******
echo '-------------------<< Verifying rewrite queries for TPCH dataset >>-------------------'
$CMDReSequel Verify tpch PostgreSQL 1 ${model} PostgreSQL

## Run Workload
#********************
echo '-------------------<< Running workload for TPCH dataset >>-------------------'
$CMDRunWorkload tpch PostgreSQL ${model}
