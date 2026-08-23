#!/bin/bash

dataset=$1
dbms=$2
baseline_name='LearnedRewrite'

exp_path="$(pwd)"

output_path="${exp_path}/LearnedRewrite-results/Rewrite/${dbms}/${dataset}-${baseline_name}"
mkdir -p "${exp_path}/LearnedRewrite-results/Rewrite/${dbms}"

rm -rf ${output_path}
mkdir -p ${output_path}

workload_path="${exp_path}/workload/${dbms}/${dataset}"
schema_path="${exp_path}/catalog/${dataset}/schema.json"
log_file_name="${exp_path}/results/learnedrewrite/runExperiment2-${dataset}-${dbms}-${baseline_name}.dat"

if [ $dataset == "publicbibenchmark" ]; then
    mkdir -p "${output_path}/queries"
fi 

cd "${exp_path}/baselines/LearnedRewrite"
source venv/bin/activate

CMD="python my_rewriter/main.py --workload-path ${workload_path} \
                    --schema-path ${schema_path} \
                    --database-name ${dataset} \
                    --dbms ${dbms} \
                    --output-path ${output_path}"


start=$(date +%s%N)
$CMD
end=$(date +%s%N)

echo ${dataset}",${dbms},"$((($end - $start) / 1000000)) >>$log_file_name
