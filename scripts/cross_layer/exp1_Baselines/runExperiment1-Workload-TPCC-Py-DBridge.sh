#!/bin/bash

dbms=$1
warehouses=$2
clients=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/${benchmark}"
log_fname="${exp_path}/results/cross_layer/py-dbridge/benchmarks/runExperiment1-${benchmark}-${dbms}"

cd "${workload_path}"
source venv/bin/activate

cd "${exp_path}/out/cross_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"

CMD="python tpcc.py ${dbms} \
                --config=${workload_path}/db.config \
                --clients=${clients} \
                --warehouses=${warehouses} \
                --duration=60 \
                --output-path=${log_fname} \
                --reset"
$CMD
