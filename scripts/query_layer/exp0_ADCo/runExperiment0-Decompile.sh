#!/bin/bash

app_path=$1
llm_model=$2
dbms=$3
dataset=$4
output_dir=${5:-"ADCo-results"}

exp_path="$(pwd)"
date=$(date '+%Y-%m-%d-%H-%M-%S')

if [ "$output_dir" = "ACo-results" ] || [ "$output_dir" = "aco" ] || [ "$output_dir" = "ACo" ]; then
    log_dir="aco"
    output_dir="ACo-results"
else
    log_dir="adco"
    output_dir="ADCo-results"
fi

output_path="${exp_path}/out/query_layer/${output_dir}/Decompile/${dbms}/${dataset}-${llm_model}"
rm -rf "$output_path"
mkdir -p "${output_path}"

mkdir -p "${exp_path}/results/query_layer/${log_dir}"
log_file_name="${exp_path}/results/query_layer/${log_dir}/Experiment0_Decompile.dat"

if [ ! -f "$log_file_name" ]; then
    echo "dataset_name,dbms,time" > "$log_file_name"
fi

cd "${exp_path}/baselines/ADCo"
source venv/bin/activate

SCRIPT="python src/code_rewriter/pydecompiler.py \
                        --input-dir ${app_path} \
                        --output-dir ${output_path}"

start=$(date +%s%N)
$SCRIPT
end=$(date +%s%N)

echo ${dataset}",${dbms},"$((($end - $start) / 1000000)) >> "$log_file_name"
