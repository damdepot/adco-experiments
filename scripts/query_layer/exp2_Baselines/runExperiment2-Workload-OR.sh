#!/bin/bash

dataset=$1
dbms=$2
llm_model=$3

exp_path="$(pwd)"
log_fname="${exp_path}/results/query_layer/runExperiment2-${dataset}-${dbms}-${llm_model}"
query_log_fname="${exp_path}/out/query_layer/log-baseline/${dbms}/${dataset}-${llm_model}"

database_path="${exp_path}/data/duckdb"
workload_path="${exp_path}/workload/databases/${dbms}/${dataset}-${llm_model}-select-OR"


for itr in $(seq 1 "$iteration"); do
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

    cd ${exp_path}

    if [ $dbms == "PostgreSQL" ]; then
     if [ -z "$PGHOST" ] || [[ "$PGHOST" == "localhost" || "$PGHOST" == "127.0.0.1" ]]; then
      ./run/query_layer/initpgSQL.sh
      sleep 10
     fi

    elif [ $dbms == "MySQL" ]; then  
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
