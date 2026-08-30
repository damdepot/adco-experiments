#!/bin/bash

dbms=$1
accounts=$2
transactions=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
log_fname="${exp_path}/results/app_layer/py-dbridge/benchmarks/runExperiment1-${benchmark}-${dbms}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

cd "${exp_path}/out/app_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"

CMD="python main.py test \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --transactions ${transactions} \
                    --output-path ${log_fname}"
$CMD
