#!/bin/bash
set -e
# Get the repository root directory (where run_report.sh is placed in scripts/exp3_Reports/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DATASET="${1:-stats-lite}"
DBMS="${2:-PostgreSQL}"

python3 "$SCRIPT_DIR/report.py" \
    --dataset "$DATASET" \
    --dbms "$DBMS" \
    --results-dir "$REPO_ROOT/results" \
    --output-dir "$REPO_ROOT/reports"
