#!/bin/bash

set -euo pipefail

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
data_path="${root_path}/data"
tpch_path="${data_path}/tpch"
kit_path="${root_path}/tools/tpch-kit"

env_file="${root_path}/.env"
if [ ! -f "$env_file" ]; then
    echo "Error: .env not found in ${root_path}. See README.md." >&2
    exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    case "$key" in ''|*[!A-Za-z0-9_]* ) continue ;; esac
    value="${line#*=}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf -v "$key" '%s' "$value"
    export "$key"
done < "$env_file"

scale="${1:-${TPCH_SCALE:-1}}"

mkdir -p "${data_path}"
rm -rf "${tpch_path}"
mkdir -p "${tpch_path}"

echo '-------------------<< Downloading TPCH dataset >>-------------------'
if [ -d "${kit_path}" ]; then
    echo "tpch-kit already exists, skipping"
else
    git clone https://github.com/dannykhant/tpch "${kit_path}"
fi

# The kit repo ships checked-in dbgen/qgen binaries built for another arch
# (x86-64), which fail here with a Rosetta loader error. Always rebuild
# from source so the binary matches this host.
case "$(uname -s)" in
    Darwin) machine="MACOS" ;;
    *) machine="LINUX" ;;
esac
cd "${kit_path}/dbgen"
make clean
make "MACHINE=${machine}" DATABASE=POSTGRESQL

echo "-------------------<< Generating TPCH dataset (scale ${scale}) >>-------------------"
export DSS_CONFIG="${kit_path}/dbgen"
export DSS_QUERY="${kit_path}/dbgen/queries"
export DSS_PATH="${tpch_path}"
cd "${kit_path}/dbgen"
./dbgen -s "${scale}"
