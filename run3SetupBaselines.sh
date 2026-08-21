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

### R-Bot
echo '-------------------<< Setting up R-Bot baseline >>-------------------'
rbot_path="${root_path}/baselines/R-Bot"
cd ${rbot_path}
setup_venv "${rbot_path}"

cd rag
unzip -oq stackoverflow-rewrite-embed.zip
# Build structure-semantics Q&A index.
../venv/bin/python rag_gen.py

### ReSequel
echo '-------------------<< Setting up ReSequel baseline >>-------------------'
resql_path="${root_path}/baselines/ReSequel"
cd ${resql_path}
setup_venv "${resql_path}"
