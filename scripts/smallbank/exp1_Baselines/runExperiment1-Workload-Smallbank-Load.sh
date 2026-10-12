#!/bin/bash
set -euo pipefail

dbms="${1:-postgres}"
accounts="${2:-${ACCOUNTS:-5000000}}"

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

CMD="python main.py load \
                    --driver ${dbms} \
                    --threads ${LOAD_THREADS:-4} \
                    --accounts ${accounts} \
                    --reset"
$CMD
