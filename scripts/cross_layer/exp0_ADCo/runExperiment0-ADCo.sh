#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"


# Rewrite
output_path="${exp_path}/out/cross_layer/ADCo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"
mkdir -p ${output_path}

cd "${exp_path}/baselines/ADCo"
source venv/bin/activate

SCRIPT="python -m src.rewriter ${codebase_path} \
                        --model ${llm_model} \
                        --output-path ${output_path}"

echo ${SCRIPT}
$SCRIPT
