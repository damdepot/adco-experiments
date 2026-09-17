#!/bin/bash

dbms=$1
warehouses=$2
clients=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/${benchmark}"
log_fname="${exp_path}/results/db_layer/ottertune/benchmarks/runExperiment1-${benchmark}-${dbms}-ottertune"

cd "${workload_path}"
source venv/bin/activate

CMD="python tpcc.py ${dbms} \
                --config=${workload_path}/db.config \
                --clients=${clients} \
                --warehouses=${warehouses} \
                --duration=60 \
                --output-path=${log_fname} \
                --reset"
$CMD
