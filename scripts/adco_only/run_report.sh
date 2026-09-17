#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RESULTS_DIR="${REPO_ROOT}/results/adco_only"
OUTPUT_DIR="${REPO_ROOT}/reports/adco_only"

mkdir -p "$OUTPUT_DIR"

if [ $# -eq 0 ]; then
    python3 "$SCRIPT_DIR/report.py" \
        --workload "all" \
        --dbms "postgres" \
        --results-dir "$RESULTS_DIR" \
        --output-dir "$OUTPUT_DIR"
else
    if [[ "$1" == --* ]]; then
        python3 "$SCRIPT_DIR/report.py" \
            --results-dir "$RESULTS_DIR" \
            --output-dir "$OUTPUT_DIR" \
            "$@"
    else
        WORKLOAD="${1:-all}"
        DBMS="${2:-postgres}"
        shift 2 2>/dev/null || shift $#
        python3 "$SCRIPT_DIR/report.py" \
            --workload "$WORKLOAD" \
            --dbms "$DBMS" \
            --results-dir "$RESULTS_DIR" \
            --output-dir "$OUTPUT_DIR" \
            "$@"
    fi
fi
