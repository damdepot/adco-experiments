#!/bin/bash

llm_model=$1
dbms=$2
warehouses=$3
clients=$4
benchmark=$5

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/${benchmark}"
log_fname="${exp_path}/results/db_layer/agenttune/benchmarks/runExperiment1-${benchmark}-${dbms}-${llm_model}"

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
