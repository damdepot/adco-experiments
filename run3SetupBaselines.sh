#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")" && pwd)"

setup_venv() {
    local dir="$1"
    cd "${dir}"
    rm -rf venv
    uv venv venv --python python3
    uv pip install --python venv/bin/python -r requirements.txt
}

### Workload generator
echo '-------------------<< Setting up workload generator >>-------------------'
workload_path="${root_path}/workload_generator"
setup_venv "${workload_path}"

### ReSequel
echo '-------------------<< Setting up ReSequel baseline >>-------------------'
resql_path="${root_path}/baselines/ReSequel"
resql_python_src="${resql_path}/src/main/python"
cd ${resql_python_src}
setup_venv "${resql_python_src}"

### R-Bot
echo '-------------------<< Setting up R-Bot baseline >>-------------------'
rbot_path="${root_path}/baselines/R-Bot"
cd ${rbot_path}
setup_venv "${rbot_path}"

cd rag
unzip -oq stackoverflow-rewrite-embed.zip
# Build structure-semantics Q&A index.
../venv/bin/python rag_gen.py

### LearnedRewrite
echo '-------------------<< Setting up LearnedRewrite baseline >>-------------------'
lr_path="${root_path}/baselines/LearnedRewrite"
cd ${lr_path}
setup_venv "${lr_path}"