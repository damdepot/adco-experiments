#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../.." && pwd)"

venv_ok() {
    [ -x "${1}/venv/bin/python" ] \
        && [ -f "${1}/.venv_hash" ] \
        && [ "$(cat "${1}/.venv_hash")" = "${2}" ]
}

setup_venv() {
    local dir="$1"
    cd "${dir}"
    local dep_files=(requirements.txt)
    if [ -f .python-version ]; then
        dep_files+=(.python-version)
    fi
    local dep_hash
    dep_hash="$(cat "${dep_files[@]}" | cksum)"
    if venv_ok "${dir}" "${dep_hash}"; then
        echo 'venv already up to date, skipping'
        return 0
    fi
    rm -rf venv
    UV_PYTHON_INSTALL_DIR="${dir}/.uv-python" uv venv venv
    UV_PYTHON_INSTALL_DIR="${dir}/.uv-python" uv pip install --python venv/bin/python -r requirements.txt
    printf '%s\n' "${dep_hash}" > .venv_hash
}

setup_venv_uv() {
    local dir="$1"
    cd "${dir}"
    local dep_files=(pyproject.toml)
    if [ -f uv.lock ]; then
        dep_files+=(uv.lock)
    fi
    if [ -f .python-version ]; then
        dep_files+=(.python-version)
    fi
    local dep_hash
    dep_hash="$(cat "${dep_files[@]}" | cksum)"
    if venv_ok "${dir}" "${dep_hash}"; then
        echo 'venv already up to date, skipping'
        return 0
    fi
    rm -rf venv
    UV_PYTHON_INSTALL_DIR="${dir}/.uv-python" uv venv venv
    UV_PYTHON_INSTALL_DIR="${dir}/.uv-python" uv pip install --python venv/bin/python -e .
    printf '%s\n' "${dep_hash}" > .venv_hash
}


### ADCo
echo '-------------------<< Setting up ADCo baseline >>-------------------'
adco_path="${root_path}/baselines/ADCo"
setup_venv_uv "${adco_path}"

### AgentTune
echo '-------------------<< Setting up AgentTune baseline >>-------------------'
agenttune_path="${root_path}/baselines/AgentTune"
setup_venv "${agenttune_path}"
