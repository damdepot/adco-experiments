#!/bin/bash
set -e
# Get the repository root directory (where run_report.sh is placed in scripts/db_layer/exp2_Reports/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RESULTS_DIR="${REPO_ROOT}/results/db_layer"
OUTPUT_DIR="${REPO_ROOT}/reports/db_layer"

WORKLOAD="${1:-all}"
DBMS="${2:-postgres}"

python3 "$SCRIPT_DIR/report.py" \
    --workload "$WORKLOAD" \
    --dbms "$DBMS" \
    --results-dir "$RESULTS_DIR" \
    --output-dir "$OUTPUT_DIR"
