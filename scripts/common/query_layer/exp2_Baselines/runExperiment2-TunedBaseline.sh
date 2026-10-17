#!/bin/bash

dataset=$1
dbms=$2
arm=$3
llm_model=${4:-}

exp_path="$(pwd)"
log_fname="${exp_path}/results/${dataset}/${arm}/benchmarks/runExperiment2-${dataset}-${dbms}${llm_model:+-${llm_model}}"
query_log_fname="${exp_path}/results/${dataset}/${arm}/${dbms}/${dataset}${llm_model:+-${llm_model}}"
mkdir -p "$(dirname "${log_fname}")" "$(dirname "${query_log_fname}")"

workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"
database_path="${exp_path}/data/duckdb"

for itr in $(seq 1 "$iteration"); do
    echo "[${arm}] iteration ${itr}/${iteration} (${dataset}/${dbms}) starting..."
    sync
    echo 3 | tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

    cd ${exp_path}

    if [ $dbms == "PostgreSQL" ]; then
     if [ -z "$PGHOST" ] || [[ "$PGHOST" == "localhost" || "$PGHOST" == "127.0.0.1" ]]; then
      ./run/setup/stats-init-pgsql.sh
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
