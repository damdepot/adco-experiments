#!/bin/bash

dataset=$1
dbms=$2
llm_model=$3

exp_path="$(pwd)"

workload_path="${exp_path}/workload/${dbms}/${dataset}"
rewrite_path="${exp_path}/R-Bot-results/Rewrite/${dbms}/${dataset}/${llm_model}"
output_path_verify="${exp_path}/R-Bot-results/Select/${dbms}/${dataset}-${llm_model}-select"

rm -rf ${output_path_verify}
mkdir -p ${output_path_verify}

if [ $dataset == "publicbibenchmark" ]; then
    mkdir -p "${output_path_verify}/queries"
fi    

verify_log_path="${exp_path}/results/r-bot/Experiment2_RBot_Verify_${dbms}_${dataset}.dat"
mkdir -p "${exp_path}/results/r-bot"

cd "${exp_path}/workload_generator"
source venv/bin/activate

CMD="python main_verify_LR.py --workload-path ${workload_path} \
                    --database-name ${dataset} \
                    --dbms ${dbms} \
                    --rewrite-path ${rewrite_path} \
                    --verify-log-path ${verify_log_path} \
                    --output-path-verify ${output_path_verify}"

$CMD