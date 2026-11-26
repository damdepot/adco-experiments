#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

RESULTS_DIR="${REPO_ROOT}/results"

WORKLOAD="${1:-all}"
DBMS="${2:-postgres}"

run_one() {
    mkdir -p "${REPO_ROOT}/reports/$1/app_layer"
    python3 "$SCRIPT_DIR/report.py" \
        --workload "$1" \
        --dbms "$DBMS" \
        --results-dir "$RESULTS_DIR" \
        --output-dir "${REPO_ROOT}/reports/$1/app_layer"
}

if [ "${WORKLOAD}" = "all" ]; then
    for wl in tpcc smallbank; do
        run_one "$wl"
    done
else
    run_one "$WORKLOAD"
fi
