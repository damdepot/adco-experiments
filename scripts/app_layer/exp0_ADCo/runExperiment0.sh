#!/bin/bash

op=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
codebase_path="${exp_path}/workload/apps/${benchmark}"

CMDADCo=./scripts/app_layer/exp0_ADCo/runExperiment0-ADCo.sh
CMDACo=./scripts/app_layer/exp0_ADCo/runExperiment0-ACo.sh

if [ "$op" == "ADCo" ]; then  
    $CMDADCo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
elif [ "$op" == "ACo" ] || [ "$op" == "Rewrite" ]; then  
    $CMDACo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
else     
    echo "Invalid operation: $op. Supported operations are: ADCo, ACo." 
fi
