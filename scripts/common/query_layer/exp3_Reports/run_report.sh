#!/bin/bash
set -e
# Get the repository root directory (where run_report.sh is placed in scripts/common/query_layer/exp3_Reports/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

DATASET="${1:-stats}"
DBMS="${2:-PostgreSQL}"

RESULTS_DIR="${RESULTS_DIR:-${REPO_ROOT}/results/${DATASET}}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/reports/${DATASET}}"

python3 "$SCRIPT_DIR/report.py" \
    --dataset "$DATASET" \
    --dbms "$DBMS" \
    --results-dir "$RESULTS_DIR" \
    --output-dir "$OUTPUT_DIR"
