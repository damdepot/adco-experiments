#!/bin/bash

llm_model=$1
dbms=$2
accounts=$3
transactions=$4
benchmark=$5

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
log_fname="${exp_path}/results/app_layer/adco/benchmarks/runExperiment1-${benchmark}-${dbms}-${llm_model}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

cd "${exp_path}/out/app_layer/ADCo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"

CMD="python main.py test \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --transactions ${transactions} \
                    --output-path ${log_fname}"
$CMD
