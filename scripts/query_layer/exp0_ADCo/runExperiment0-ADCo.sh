#!/bin/bash

dataset=$1
compiled_codebase_path=$2
llm_model=$3
dbms=$4

exp_path="$(pwd)"

# Rewrite
output_path="${exp_path}/out/query_layer/ADCo-results/Rewrite/${dbms}/${dataset}-${llm_model}"
mkdir -p "${exp_path}/out/query_layer/ADCo-results/Rewrite"
mkdir -p ${output_path}

cd "${exp_path}/baselines/ADCo"
source venv/bin/activate

SCRIPT="python -m src.code_rewriter ${compiled_codebase_path} \
                        --model ${llm_model} \
                        --output-path ${output_path}"

echo ${SCRIPT}
$SCRIPT
