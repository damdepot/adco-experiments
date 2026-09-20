#!/bin/bash
set -e
# Get the repository root directory (where run_report.sh is placed in scripts/adco_only/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RESULTS_DIR="${REPO_ROOT}/results/adco_only"
OUTPUT_DIR="${REPO_ROOT}/reports/adco_only"

mkdir -p "$OUTPUT_DIR"

if [[ "${1:-}" == --* ]]; then
    python3 "$SCRIPT_DIR/report.py" \
        --results-dir "$RESULTS_DIR" \
        --output-dir "$OUTPUT_DIR" \
        "$@"
else
    WORKLOAD="${1:-all}"
    DBMS="${2:-postgres}"

    python3 "$SCRIPT_DIR/report.py" \
        --workload "$WORKLOAD" \
        --dbms "$DBMS" \
        --results-dir "$RESULTS_DIR" \
        --output-dir "$OUTPUT_DIR"
fi
