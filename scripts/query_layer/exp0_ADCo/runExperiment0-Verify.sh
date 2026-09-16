#!/bin/bash

dataset=$1
workload_path=$2
llm_model=$3
dbms=$4
runner_dbms=$5
output_dir=${6:-"ADCo-results"}
threads=${7:-$THREADS}

exp_path="$(pwd)"

if [ "$output_dir" = "ACo-results" ] || [ "$output_dir" = "aco" ] || [ "$output_dir" = "ACo" ]; then
    log_dir="aco"
    output_dir="ACo-results"
else
    log_dir="adco"
    output_dir="ADCo-results"
fi

rewrite_path="${exp_path}/out/query_layer/${output_dir}/Decompile/${dbms}/${dataset}-${llm_model}"
output_path_verify="${exp_path}/out/query_layer/${output_dir}/Select/${dbms}/${dataset}-${llm_model}-select"
database_path="${exp_path}/data/duckdb"

rm -rf "${output_path_verify}"
mkdir -p "${output_path_verify}"

if [ "$dataset" == "publicbibenchmark" ]; then
    mkdir -p "${output_path_verify}/queries"
fi    

if [ "$dbms" == "PostgreSQL" ]; then
    if [ -z "$PGHOST" ] || [[ "$PGHOST" == "localhost" || "$PGHOST" == "127.0.0.1" ]]; then
        ./run/query_layer/initpgSQL.sh
        sleep 10
    fi
elif [ "$dbms" == "MySQL" ]; then  
    ./initMySQL.sh   
    sleep 10 
fi 

mkdir -p "${exp_path}/results/query_layer/${log_dir}"
verify_log_path="${exp_path}/results/query_layer/${log_dir}/Experiment0_Verify.dat"

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