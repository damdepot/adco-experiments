#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4


exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
output_path="${exp_path}/out/db_layer/ADCo-results/Knob-Tune/${dbms}/${benchmark}-${llm_model}"
mkdir -p ${output_path}

cd "${exp_path}/baselines/ADCo"

uv run python -m src.adco ${codebase_path} \
    --model ${llm_model} \
    --db-type ${dbms} \
    --db-name ${benchmark} \
    --cpu-cores 2 \
    --memory 8 \
    --sandbox-dir ${output_path} \
    --knob-path ${output_path} \
    --log-file ${output_path}/knob_tuner.log \
    --output-path ${output_path}/result.json \
    --verbose
