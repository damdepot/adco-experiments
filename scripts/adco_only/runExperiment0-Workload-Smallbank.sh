#!/bin/bash

llm_model=$1
dbms=$2
accounts=$3
transactions=$4
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
log_fname="${exp_path}/results/adco_only/${res_name}/benchmarks/runExperiment1-${benchmark}-${dbms}-${llm_model}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

if [ "$dir_name" == "aco" ] || [ "$dir_name" == "ACo" ] || [ "$dir_name" == "adco" ] || [ "$dir_name" == "ADCo" ]; then
    cd "${exp_path}/out/adco_only/${out_name}/Rewrite/${dbms}/${benchmark}-${llm_model}"
fi

CMD="python main.py test \
                    --driver ${dbms} \
                    --threads 8 \
                    --accounts ${accounts} \
                    --transactions ${transactions} \
                    --output-path ${log_fname}"
$CMD
