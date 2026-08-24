#!/bin/bash

op=$1
dataset=$2
dbms=$3
scale=$4
llm_model=$5
runner_dbms=$6
sample_fraction=$7
exp_path="$(pwd)"

workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"

CMDCompile=./scripts/exp0_ADCo/runExperiment0-Compile.sh
CMDADCo=./scripts/exp0_ADCo/runExperiment0-ADCo.sh
CMDDecompile=./scripts/exp0_ADCo/runExperiment0-Decompile.sh
CMDVerify=./scripts/exp0_ADCo/runExperiment0-Verify.sh

if [ "$op" == "Compile" ]; then
    $CMDCompile ${dataset} ${workload_path} ${llm_model} ${dbms}

elif [ "$op" == "Rewrite" ]; then  
    codebase_path="${exp_path}/ADCo-results/Compile/${dbms}/${dataset}-${llm_model}"
    $CMDADCo ${dataset} ${codebase_path} ${llm_model} ${dbms}  

elif [ "$op" == "Decompile" ]; then
    rewrite_path="${exp_path}/ADCo-results/Rewrite/${dbms}/${dataset}-${llm_model}"
    $CMDDecompile ${dataset} ${rewrite_path} ${llm_model} ${dbms}

elif [ "$op" == "Verify" ]; then
    $CMDVerify ${dataset} ${workload_path} ${llm_model} ${dbms} ${runner_dbms}

else     
    $CMDADCo ${dataset} ${workload_path} ${llm_model} ${dbms}
fi 
