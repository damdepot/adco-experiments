#!/bin/bash

op=$1
dataset=$2
dbms=$3
scale=$4
llm_model=$5
runner_dbms=$6
sample_fraction=$7
exp_path="$(pwd)"

catalog_dir="${exp_path}/catalog"
mkdir -p ${catalog_dir}

if [ $dataset == "tpcds" ] || [ $dataset == "tpch" ]; then
    catalog_path="${catalog_dir}/${dataset}-s${scale}"
else 
    catalog_path="${catalog_dir}/${dataset}"
fi 

mkdir -p ${catalog_path}

workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"

CMDBuildCatalog=./scripts/stats/exp1_ReSequel/runExperiment1-BuildCatalog.sh
CMDTemplatization=./scripts/stats/exp1_ReSequel/runExperiment1-Templatization.sh
CMDReconstruct=./scripts/stats/exp1_ReSequel/runExperiment1-Reconstruct.sh
CMDLabeling=./scripts/stats/exp1_ReSequel/runExperiment1-Label.sh
CMDVerify=./scripts/stats/exp1_ReSequel/runExperiment1-Verify.sh
CMDVerifyOR=./scripts/stats/exp1_ReSequel/runExperiment1-Verify-OR.sh
CMDDownsampling=./scripts/stats/exp1_ReSequel/runExperiment1-Downsampling.sh
CMDJudge=./scripts/stats/exp1_ReSequel/runExperiment1-Judge.sh
CMDImplement="./scripts/stats/exp1_ReSequel/runExperiment1-Implement.sh ${dataset} ${catalog_path} ${dbms}"
CMDReSequel="./scripts/stats/exp1_ReSequel/runExperiment1-ReSequel.sh ${dataset} ${catalog_path} ${llm_model} ${dbms}"


if [ $op == "BuildCatalog" ]; then
    $CMDBuildCatalog ${dataset} ${catalog_path}

elif [ $op == "Templatization" ]; then  
    $CMDTemplatization ${dataset} ${workload_path} ${dbms}  

elif [ $op == "Generate" ]; then
    export generate_list="--query-list"
    template_path="${exp_path}/out/query_layer/ReSequel-results/Template/${dbms}/${dataset}-template"
    $CMDReSequel ${template_path}

elif [ $op == "Reconstruct" ]; then  
    $CMDReconstruct ${dataset} ${workload_path} ${dbms} ${llm_model} 

elif [ $op == "Labeling" ]; then  
    $CMDLabeling ${dataset} ${workload_path} ${dbms} ${llm_model}     

elif [ $op == "Verify" ]; then  
    $CMDVerify ${dataset} ${workload_path} ${dbms} ${llm_model} ${runner_dbms}

elif [ $op == "VerifyOR" ]; then  
    $CMDVerifyOR ${dataset} ${workload_path} ${dbms} ${llm_model} ${runner_dbms}

elif [ $op == "Downsampling" ]; then  
    $CMDDownsampling ${dataset} ${workload_path} ${dbms} ${llm_model} ${catalog_path} ${sample_fraction}

elif [ $op == "Judge" ]; then  
    template_path="${exp_path}/out/query_layer/ReSequel-results/Template/${dbms}/${dataset}-template"
    $CMDJudge  ${dataset} ${catalog_path} ${llm_model} ${dbms}  ${template_path}

elif [ $op == "Implement" ]; then
     $CMDImplement ${llm_model}

else     
    export generate_list=""
    $CMDReSequel ${llm_model}
fi 

