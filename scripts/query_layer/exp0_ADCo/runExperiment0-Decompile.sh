#!/bin/bash

dataset=$1
app_path=$2
llm_model=$3
dbms=$4

exp_path="$(pwd)"
date=$(date '+%Y-%m-%d-%H-%M-%S')

output_path="${exp_path}/out/db_layer/ADCo-results/Decompile/${dbms}/${dataset}-${llm_model}"
rm -rf $output_path
mkdir -p ${output_path}

log_file_name="${exp_path}/results/adco/Experiment0_Decompile.dat"

if [ ! -f "$log_file_name" ]; then
    echo "dataset_name,dbms,time" > $log_file_name
fi

if [ "$dataset" == "publickbibenchmark" ]; then
    workload_path="${workload_path}/queries"
fi

cd "${exp_path}/baselines/ADCo"
source venv/bin/activate

SCRIPT="python src/rewriter/pydecompiler.py \
                        --input-dir ${app_path} \
                        --output-dir ${output_path}"

start=$(date +%s%N)
$SCRIPT
end=$(date +%s%N)

echo ${dataset}",${dbms},"$((($end - $start) / 1000000)) >>$log_file_name
