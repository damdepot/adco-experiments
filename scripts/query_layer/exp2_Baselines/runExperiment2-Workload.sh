#!/bin/bash

dataset=$1
dbms=$2
llm_model=$3
target_sys=$4

exp_path="$(pwd)"

if [ "$target_sys" = "aco" ] || [ "$target_sys" = "ACo" ] || [ "$target_sys" = "ACo-results" ]; then
    result_benchmark_path="results/query_layer/aco/benchmarks"
    result_output_path="out/query_layer/ACo-results"
elif [ "$target_sys" = "adco" ] || [ "$target_sys" = "ADCo" ] || [ "$target_sys" = "ADCo-results" ]; then
    result_benchmark_path="results/query_layer/adco/benchmarks"
    result_output_path="out/query_layer/ADCo-results"
else
    result_benchmark_path="${result_benchmark_path:-results/query_layer/adco/benchmarks}"
    result_output_path="${result_output_path:-out/query_layer/ADCo-results}"
fi

mkdir -p "${exp_path}/${result_benchmark_path}"
mkdir -p "${exp_path}/out/query_layer/log-baseline/${dbms}"

log_fname="${exp_path}/${result_benchmark_path}/runExperiment2-${dataset}-${dbms}-${llm_model}"
query_log_fname="${exp_path}/out/query_layer/log-baseline/${dbms}/${dataset}-${llm_model}"

workload_path="${exp_path}/${result_output_path}/Select/${dbms}/${dataset}-${llm_model}-select"
database_path="${exp_path}/data/duckdb"

for itr in $(seq 1 "${iteration:-1}"); do
    sync
    echo 3 | tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

    cd ${exp_path}

    if [ "$dbms" == "PostgreSQL" ]; then
     if [ -z "$PGHOST" ] || [[ "$PGHOST" == "localhost" || "$PGHOST" == "127.0.0.1" ]]; then
      ./run/query_layer/initpgSQL.sh
      sleep 10
     fi

    elif [ "$dbms" == "MySQL" ]; then  
        ./initMySQL.sh   
        sleep 10 
    fi   

    cd "${exp_path}/workload/src"
    source venv/bin/activate

    CMD="python main.py --workload-path ${workload_path} \
                        --database-name ${dataset} \
                        --database-path ${database_path} \
                        --dbms ${dbms} \
                        --iterations ${itr} \
                        --query-log-path ${query_log_fname} \
                        --output-path ${log_fname}"

    $CMD
done
