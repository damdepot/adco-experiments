#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
output_path="${exp_path}/out/query_layer/ACo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"
mkdir -p ${output_path}

cd "${exp_path}/baselines/ADCo"

uv run python -m src.adco ${codebase_path} \
    --model ${llm_model} \
    --mode rewrite-only \
    --sandbox-dir ${output_path} \
    --output-path ${output_path}/result.json \
    --verbose
