#!/bin/bash

dbms=$1
accounts=$2
transactions=$3

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
log_fname="${exp_path}/results/cross_layer/baseline/benchmarks/runExperiment1-smallbank-${dbms}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

CMD="python main.py test \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --transactions ${transactions} \
                    --output-path ${log_fname}"
$CMD
