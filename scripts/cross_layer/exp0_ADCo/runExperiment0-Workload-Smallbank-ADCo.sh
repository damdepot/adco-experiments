#!/bin/bash

llm_model=$1
dbms=$2
accounts=$3
transactions=$4
benchmark=$5

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"


cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

cd "${exp_path}/out/cross_layer/ADCo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"

CMD="python main.py run \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --transactions ${transactions}"
$CMD
