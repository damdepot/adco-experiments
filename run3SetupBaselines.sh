#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")" && pwd)"

venv_ok() {
    [ -x "${1}/venv/bin/python" ] \
        && [ -f "${1}/.venv_hash" ] \
        && [ "$(cat "${1}/.venv_hash")" = "${2}" ]
}

setup_venv() {
    local dir="$1"
    cd "${dir}"
    local dep_hash
    dep_hash="$(cat requirements.txt | cksum)"
    if venv_ok "${dir}" "${dep_hash}"; then
        echo 'venv already up to date, skipping'
        return 0
    fi
    rm -rf venv
    uv venv venv --python python3
    uv pip install --python venv/bin/python -r requirements.txt
    printf '%s\n' "${dep_hash}" > .venv_hash
}

setup_venv_uv() {
    local dir="$1"
    cd "${dir}"
    local dep_files=(pyproject.toml)
    if [ -f uv.lock ]; then
        dep_files+=(uv.lock)
    fi
    local dep_hash
    dep_hash="$(cat "${dep_files[@]}" | cksum)"
    if venv_ok "${dir}" "${dep_hash}"; then
        echo 'venv already up to date, skipping'
        return 0
    fi
    rm -rf venv
    uv venv venv --python python3
    uv pip install --python venv/bin/python -e .
    printf '%s\n' "${dep_hash}" > .venv_hash
}

### Workload generator
echo '-------------------<< Setting up workload generator >>-------------------'
workload_path="${root_path}/workload/src"
setup_venv "${workload_path}"

### ADCo
echo '-------------------<< Setting up ADCo baseline >>-------------------'
adco_path="${root_path}/baselines/ADCo"
setup_venv_uv "${adco_path}"

### LearnedRewrite
echo '-------------------<< Setting up LearnedRewrite baseline >>-------------------'
lr_path="${root_path}/baselines/LearnedRewrite"
setup_venv "${lr_path}"

### ReSequel
echo '-------------------<< Setting up ReSequel baseline >>-------------------'
resql_python_src="${root_path}/baselines/ReSequel/src/main/python"
setup_venv "${resql_python_src}"

### R-Bot
echo '-------------------<< Setting up R-Bot baseline >>-------------------'
rbot_path="${root_path}/baselines/R-Bot"
setup_venv "${rbot_path}"

cd rag
unzip -oq stackoverflow-rewrite-embed.zip
# Build structure-semantics Q&A index.
../venv/bin/python rag_gen.py
