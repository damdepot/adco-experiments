#!/bin/bash

dataset=$1
dbms=$2
threads=${3:-$THREADS}

exp_path="$(pwd)"

workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"
rewrite_path="${exp_path}/out/query_layer/LearnedRewrite-results/Rewrite/${dbms}/${dataset}-LearnedRewrite"
output_path_verify="${exp_path}/out/query_layer/LearnedRewrite-results/Select/${dbms}/${dataset}-LearnedRewrite-select"

rm -rf ${output_path_verify}
mkdir -p ${output_path_verify}

if [ $dataset == "publicbibenchmark" ]; then
    mkdir -p "${output_path_verify}/queries"
fi    

verify_log_path="${exp_path}/out/query_layer/LearnedRewrite-results/Experiment1_Verify.dat"

cd "${exp_path}/workload/src"
source venv/bin/activate

CMD="python main_verify_LR.py --workload-path ${workload_path} \
                    --database-name ${dataset} \
                    --dbms ${dbms} \
                    --rewrite-path ${rewrite_path} \
                    --verify-log-path ${verify_log_path} \
                    --output-path-verify ${output_path_verify} \
                    --verbose"

if [ -n "$threads" ]; then
    CMD="${CMD} --threads ${threads}"
fi

$CMD