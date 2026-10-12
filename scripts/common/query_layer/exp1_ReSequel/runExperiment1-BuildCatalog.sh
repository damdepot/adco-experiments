#!/bin/bash

dataset=$1
catalog_path=$2
exp_path="$(pwd)"

log_file_name="${exp_path}/${RESULTS_DATASET_DIR:-results/${dataset}}/resequel/Experiment1_Catalog.dat"
mkdir -p "$(dirname "${log_file_name}")"

cd "${exp_path}/baselines/ReSequel/src/main/python"
source venv/bin/activate

SCRIPT="python main.py --dataset-name ${dataset} \
                       --prepare-data-catalog \
                       --catalog-path ${catalog_path}"

start=$(date +%s%N)
$SCRIPT
end=$(date +%s%N)

echo ${dataset}",PostgreSQL,"$((($end - $start) / 1000000)) >>$log_file_name
