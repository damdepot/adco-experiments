#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RESULTS_DIR="${REPO_ROOT}/results/app_layer"
OUTPUT_DIR="${REPO_ROOT}/reports/app_layer"

WORKLOAD="${1:-all}"
DBMS="${2:-postgres}"

python3 "$SCRIPT_DIR/report.py" \
    --workload "$WORKLOAD" \
    --dbms "$DBMS" \
    --results-dir "$RESULTS_DIR" \
    --output-dir "$OUTPUT_DIR"
