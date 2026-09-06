#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"


# Tune
output_path="${exp_path}/out/app_layer/ADCo-results/Knob-Tune/${dbms}/${benchmark}-${llm_model}"
mkdir -p ${output_path}

cd "${exp_path}/baselines/ADCo"
source venv/bin/activate

SCRIPT="python -m src.knob_tuner ${codebase_path} \
                        --model ${llm_model} \
                        --db-type ${dbms} \
                        --cpu-cores 2 \
                        --memory 2 \
                        --knob-path ${output_path} \
                        --log-file ${output_path}/knob_tuner.log \
                        --output-path ${output_path}/result.json"

echo ${SCRIPT}
$SCRIPT
