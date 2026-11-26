#!/usr/bin/env bash
# Verify every SmallBank rewrite arm whose tree already exists on disk.
# Read-only with respect to artifacts: never generates or tunes.
# Re-runs verification even when a fresh verdict exists (REVERIFY=1).
#
# Usage: run_all_verify.sh [dbms=postgres]
#   MODEL=...     rewrite model directory (default gemini-3.5-flash-lite)
#   DRY_RUN=1     print the arms that would be verified, then exit
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
DBMS="${1:-postgres}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"
APP="out/app_layer"

ARMS=()
add() {
    local arm="$1" driver="$2"
    if [ -f "${driver}" ]; then
        ARMS+=("${arm}")
    fi
}

add naive-llm "${APP}/NaiveLLM-results/Rewrite/${DBMS}/smallbank-NaiveLLM/drivers/postgresdriver.py"
add aco "${APP}/ACo-results/Rewrite/${DBMS}/smallbank-${MODEL}/drivers/postgresdriver.py"
add adco "${APP}/ADCo-results/Rewrite/${DBMS}/smallbank-${MODEL}/drivers/postgresdriver.py"
add py-dbridge "${APP}/Py-DBridge-results/Rewrite/${DBMS}/smallbank-Py-DBridge/drivers/postgresdriver.py"
add naive-llm-agenttune "${APP}/NaiveLLM-results/naive-llm-agenttune/Rewrite/${DBMS}/smallbank-NaiveLLM/drivers/postgresdriver.py"
add agenttune-naive-llm "${APP}/NaiveLLM-results/agenttune-naive-llm/Rewrite/${DBMS}/smallbank-NaiveLLM/drivers/postgresdriver.py"

if [ "${#ARMS[@]}" -eq 0 ]; then
    echo "No SmallBank rewrite artifacts under ${APP}/ (dbms=${DBMS}, model=${MODEL})." >&2
    exit 1
fi
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "Would verify: ${ARMS[*]}"
    exit 0
fi

echo "Verifying ${#ARMS[@]} arm(s): ${ARMS[*]}"
REVERIFY=1 exec "${ROOT}/run/smallbank/run_verify.sh" "${DBMS}" "$(IFS=,; echo "${ARMS[*]}")"
