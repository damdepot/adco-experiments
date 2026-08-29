#!/bin/bash

source_path=$1
source_file=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"

source="${exp_path}/${source_path}/${source_file}"

# Rewrite
output_path="${exp_path}/out/cross_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"
mkdir -p ${output_path}

cp -r ${source_path}/* ${output_path}/

cd "${exp_path}/baselines/Py-DBridge"
source venv/bin/activate

SCRIPT="python -m src.cli ${source} \
                        -o ${output_path}/${source_file} \
                        --db ${dbms}"

echo ${SCRIPT}
$SCRIPT
