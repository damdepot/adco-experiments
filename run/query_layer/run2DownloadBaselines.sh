#!/bin/bash

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
baseline_path="${root_path}/baselines"

mkdir -p ${baseline_path}
cd ${baseline_path}


download_branch() {
    local url="$1" name="$2" branch="$3"
    echo "-------------------<< Downloading ${name} >>-------------------"
    if [ -d "${name}" ]; then
        echo "${name} already exists, skipping"
    else
        git clone -b "${branch}" --depth 1 "${url}" "${name}"
    fi
}


download_branch https://github.com/damdepot/ADCo.git ADCo develop
download_branch https://github.com/dannykhant/learnedrewrite.git LearnedRewrite main
download_branch https://github.com/dannykhant/resequel.git ReSequel main
download_branch https://github.com/dannykhant/r-bot.git R-Bot main
