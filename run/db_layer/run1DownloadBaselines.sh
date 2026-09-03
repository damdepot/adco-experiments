#!/bin/bash

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
baseline_path="${root_path}/baselines"

mkdir -p ${baseline_path}
cd ${baseline_path}

download() {
    local url="$1" name="$2"
    echo "-------------------<< Downloading ${name} >>-------------------"
    if [ -d "${name}" ]; then
        echo "${name} already exists, skipping"
    else
        git clone --depth 1 "${url}" "${name}"
    fi
}

download https://github.com/dannykhant/agenttune.git AgentTune
