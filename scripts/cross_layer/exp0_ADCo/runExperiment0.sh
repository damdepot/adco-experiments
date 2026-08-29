#!/bin/bash

op=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"

codebase_path="${exp_path}/workload/apps/${benchmark}"

CMDADCo=./scripts/cross_layer/exp0_ADCo/runExperiment0-ADCo.sh


if [ "$op" == "Rewrite" ]; then  
    $CMDADCo ${codebase_path} ${llm_model} ${dbms} ${benchmark}

else     
    $CMDADCo ${codebase_path} ${llm_model} ${dbms} ${benchmark}
fi 
