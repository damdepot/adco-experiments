#!/bin/bash

root_path="$(cd "$(dirname "$0")/.." && pwd)"
workload_path="${root_path}/workload/apps"

mkdir -p ${workload_path}
cd ${workload_path}

download() {
    local url="$1" name="$2"
    echo "-------------------<< Downloading ${name} >>-------------------"
    if [ -d "${name}" ]; then
        echo "${name} already exists, skipping"
    else
        git clone --depth 1 "${url}" "${name}"
    fi
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


echo '-------------------<< Downloading workload generator >>-------------------'
download https://github.com/dannykhant/py-smallbank.git smallbank
download https://github.com/dannykhant/py-tpcc-python3.git tpcc

echo '-------------------<< Setting up Smallbank >>-------------------'
smallbank_path="${workload_path}/smallbank"
setup_venv_uv "${smallbank_path}"

echo '-------------------<< Setting up TPC-C >>-------------------'
tpcc-path="${workload_path}/tpcc"
setup_venv_uv "${tpcc-path}"