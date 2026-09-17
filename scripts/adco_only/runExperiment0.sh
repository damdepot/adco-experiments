#!/bin/bash

op=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../.." && pwd)"
codebase_path="${exp_path}/workload/apps/${benchmark}"

CMDACo=./scripts/adco_only/runExperiment0-ACo.sh
CMDDCo=./scripts/adco_only/runExperiment0-DCo.sh
CMDADCo=./scripts/adco_only/runExperiment0-ADCo.sh

if [ "$op" == "ACo" ] || [ "$op" == "aco" ] || [ "$op" == "Rewrite" ]; then
    $CMDACo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
elif [ "$op" == "DCo" ] || [ "$op" == "dco" ]; then
    $CMDDCo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
elif [ "$op" == "ADCo" ] || [ "$op" == "adco" ]; then
    $CMDADCo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
else
    echo "Invalid operation: $op. Supported operations are: ACo, DCo, ADCo."
fi
