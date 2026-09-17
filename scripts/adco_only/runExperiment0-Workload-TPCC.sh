#!/bin/bash

llm_model=$1
dbms=$2
warehouses=$3
clients=$4
benchmark=$5
dir_name=$6

if [ "$dir_name" == "aco" ] || [ "$dir_name" == "ACo" ]; then
    out_name="ACo-results"
    res_name="aco"
elif [ "$dir_name" == "adco" ] || [ "$dir_name" == "ADCo" ]; then
    out_name="ADCo-results"
    res_name="adco"
else
    out_name="DCo-results"
    res_name="dco"
fi

exp_path="$(cd "$(dirname "$0")/../.." && pwd)"
workload_path="${exp_path}/workload/apps/${benchmark}"
log_fname="${exp_path}/results/adco_only/${res_name}/benchmarks/runExperiment1-${benchmark}-${dbms}-${llm_model}"

cd "${workload_path}"
source venv/bin/activate

if [ "$dir_name" == "aco" ] || [ "$dir_name" == "ACo" ] || [ "$dir_name" == "adco" ] || [ "$dir_name" == "ADCo" ]; then
    cd "${exp_path}/out/adco_only/${out_name}/Rewrite/${dbms}/${benchmark}-${llm_model}"
fi

CMD="python tpcc.py ${dbms} \
                --config=${workload_path}/db.config \
                --clients=${clients} \
                --warehouses=${warehouses} \
                --duration=60 \
                --output-path=${log_fname} \
                --reset"
$CMD
