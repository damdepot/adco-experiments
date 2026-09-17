#!/bin/bash

op=$1
dataset=$2
dbms=$3
scale=$4
llm_model=$5
type=${6:-"adco"}

exp_path="$(pwd)"
workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"

CMDCompile=./scripts/query_layer/exp0_ADCo/runExperiment0-Compile.sh
CMDACo=./scripts/query_layer/exp0_ADCo/runExperiment0-ACo.sh
CMDADCo=./scripts/query_layer/exp0_ADCo/runExperiment0-ADCo.sh
CMDDecompile=./scripts/query_layer/exp0_ADCo/runExperiment0-Decompile.sh
CMDVerify=./scripts/query_layer/exp0_ADCo/runExperiment0-Verify.sh

if [ "$type" = "adco" ] || [ "$type" = "ADCo" ] || [ "$type" = "ADCo-results" ]; then
    res_dir="ADCo-results"
    if [ "$op" == "Compile" ]; then
        $CMDCompile ${workload_path} ${llm_model} ${dbms} ${dataset} ${res_dir}
    elif [ "$op" == "Rewrite" ] || [ "$op" == "ADCo" ]; then
        codebase_path="${exp_path}/out/query_layer/${res_dir}/Compile/${dbms}/${dataset}-${llm_model}"
        $CMDADCo ${codebase_path} ${llm_model} ${dbms} ${dataset}
    elif [ "$op" == "Decompile" ]; then
        rewrite_path="${exp_path}/out/query_layer/${res_dir}/Rewrite/${dbms}/${dataset}-${llm_model}"
        $CMDDecompile ${rewrite_path} ${llm_model} ${dbms} ${dataset} ${res_dir}
    elif [ "$op" == "Verify" ]; then
        $CMDVerify ${dataset} ${workload_path} ${llm_model} ${dbms} ${dbms} ${res_dir} ${THREADS}
    else
        echo "Invalid operation: $op. Supported operations are: Compile, Rewrite (or ADCo), Decompile, Verify."
    fi
elif [ "$type" = "aco" ] || [ "$type" = "ACo" ] || [ "$type" = "ACo-results" ]; then
    res_dir="ACo-results"
    if [ "$op" == "Compile" ]; then
        $CMDCompile ${workload_path} ${llm_model} ${dbms} ${dataset} ${res_dir}
    elif [ "$op" == "Rewrite" ] || [ "$op" == "ACo" ]; then
        codebase_path="${exp_path}/out/query_layer/${res_dir}/Compile/${dbms}/${dataset}-${llm_model}"
        $CMDACo ${codebase_path} ${llm_model} ${dbms} ${dataset}
    elif [ "$op" == "Decompile" ]; then
        rewrite_path="${exp_path}/out/query_layer/${res_dir}/Rewrite/${dbms}/${dataset}-${llm_model}"
        $CMDDecompile ${rewrite_path} ${llm_model} ${dbms} ${dataset} ${res_dir}
    elif [ "$op" == "Verify" ]; then
        $CMDVerify ${dataset} ${workload_path} ${llm_model} ${dbms} ${dbms} ${res_dir} ${THREADS}
    else
        echo "Invalid operation: $op. Supported operations are: Compile, Rewrite (or ACo), Decompile, Verify."
    fi
else
    echo "Invalid type: $type. Supported types are: adco, aco."
fi