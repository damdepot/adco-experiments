#!/bin/bash
set -e
# Get the repository root directory (where run_report.sh is placed in scripts/stats/exp3_Reports/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RESULTS_DIR="${REPO_ROOT}/results/stats"
OUTPUT_DIR="${REPO_ROOT}/reports/stats"

DATASET="${1:-stats}"
DBMS="${2:-PostgreSQL}"

python3 "$SCRIPT_DIR/report.py" \
    --dataset "$DATASET" \
    --dbms "$DBMS" \
    --results-dir "$RESULTS_DIR" \
    --output-dir "$OUTPUT_DIR"
