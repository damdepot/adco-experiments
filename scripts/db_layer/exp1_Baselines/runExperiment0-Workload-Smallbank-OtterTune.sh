#!/bin/bash

dbms=$1
accounts=$2
transactions=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
log_fname="${exp_path}/results/db_layer/ottertune/benchmarks/runExperiment1-${benchmark}-${dbms}-ottertune"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

CMD="python main.py test \
                    --driver ${dbms} \
                    --threads 8 \
                    --accounts ${accounts} \
                    --transactions ${transactions} \
                    --output-path ${log_fname}"
$CMD
