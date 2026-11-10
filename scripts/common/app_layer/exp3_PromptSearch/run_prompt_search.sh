#!/usr/bin/env bash
# One-time offline prompt search for the Naive-LLM app-layer baseline.
# Usage: run_prompt_search.sh <benchmark: tpcc|smallbank> [dbms=postgres]
#        [model=$MODEL|gemini-3.5-flash-lite] [reps=2]
#
# Evaluates the current naive prompt (control) plus every
# baselines/NaiveLLM/prompts/*.txt on the real benchmark, scores each
# (median TOTAL txn/s across reps), records the result, and prints the winner.
# Scratch output lives under out/ (never results/): run_comparison.sh globs
# results/**/*.csv recursively, so search runs must not leak into that tree.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/scripts/_lib/bench_lib.sh"

BENCHMARK="${1:-}"
DBMS="${2:-postgres}"
SEARCH_MODEL="${3:-${MODEL:-gemini-3.5-flash-lite}}"
REPS="${4:-2}"

if [ "${BENCHMARK}" != "tpcc" ] && [ "${BENCHMARK}" != "smallbank" ]; then
    echo "Usage: $(basename "$0") <benchmark: tpcc|smallbank> [dbms=postgres] [model] [reps=2]" >&2
    exit 2
fi
if ! [[ "${REPS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: reps must be a positive integer (got '${REPS}')" >&2
    exit 2
fi

if [ ! -x "${ROOT}/workload/apps/${BENCHMARK}/venv/bin/python" ]; then
    echo "ERROR: ${BENCHMARK} workload venv missing; run ./run/setup/app-setup-workloads.sh" >&2
    exit 1
fi
if [ ! -x "${ROOT}/baselines/NaiveLLM/venv/bin/python" ]; then
    echo "ERROR: NaiveLLM venv missing; run ./run/setup/app-setup-baselines.sh" >&2
    exit 1
fi

bench_lock "${ROOT}"

SCRATCH="out/app_layer/NaiveLLM-search-results"
PROMPT_DIR="${ROOT}/baselines/NaiveLLM/prompts"
REWRITE_DRIVER="${ROOT}/scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh"

if [ "${BENCHMARK}" = "tpcc" ]; then
    DB="tpcc"
    SEED_DB="tpcc_seed"
    SOURCE_PATH="workload/apps/tpcc"
    ENTRY_FILE="tpcc.py"
    RUNNER="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh"
    export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"
    SEED_USED=""
else
    DB="smallbank"
    SEED_DB="smallbank_seed"
    SOURCE_PATH="workload/apps/smallbank"
    ENTRY_FILE="main.py"
    RUNNER="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh"
    export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"
    # Held-out workload seed for the search; the reported arm keeps the default 42.
    export SMALLBANK_SEED=1337
    SEED_USED="${SMALLBANK_SEED}"
fi

# Pin the measurement conditions explicitly: workload runners read these before
# sourcing bench_lib, so the values must already be in the environment.
export REPS SMOKE_SECS="${SMOKE_SECS:-20}"
if [ "${BENCHMARK}" = "tpcc" ]; then
    export TPCC_DURATION TPCC_WARMUP TPCC_WAREHOUSES TPCC_CLIENTS
else
    export SMALLBANK_ACCOUNTS SMALLBANK_TRANSACTIONS SMALLBANK_CLIENTS
    export SMALLBANK_WARMUP_ACCOUNTS SMALLBANK_WARMUP_TRANSACTIONS
fi

# Candidate ids: control (no prompt file) + sorted, non-empty prompt basenames.
CANDIDATE_IDS=("control")
if [ -d "${PROMPT_DIR}" ]; then
    while IFS= read -r prompt_path; do
        if [ -z "$(tr -d '[:space:]' < "${prompt_path}")" ]; then
            echo "Skipping empty prompt: ${prompt_path}" >&2
            continue
        fi
        candidate_id="$(basename "${prompt_path}" .txt)"
        case "${candidate_id}" in
            control)
                echo "WARNING: skipping prompt '${prompt_path}' (id 'control' is reserved)." >&2
                continue
                ;;
            selected-*)
                # Promoted winners are outputs of a previous search, not candidates.
                continue
                ;;
        esac
        CANDIDATE_IDS+=("${candidate_id}")
    done < <(find "${PROMPT_DIR}" -maxdepth 1 -type f -name '*.txt' -print | sort)
else
    echo "WARNING: prompt directory ${PROMPT_DIR} not found; searching control only." >&2
fi

# sha256 over the rewritten driver + entry file contents (whichever tool exists).
combined_sha256() {
    local driver="$1" entry="$2"
    if [ ! -f "${driver}" ] || [ ! -f "${entry}" ]; then
        return 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        cat "${driver}" "${entry}" | sha256sum | awk '{print $1}'
    else
        cat "${driver}" "${entry}" | shasum -a 256 | awk '{print $1}'
    fi
}

mkdir -p "${ROOT}/${SCRATCH}"
SCORES_TSV="${ROOT}/${SCRATCH}/scores.tsv"
: > "${SCORES_TSV}"

echo "----------------->> Prompt search: ${BENCHMARK} (${DBMS}), model=${SEARCH_MODEL}, reps=${REPS}, seed_db=${SEED_DB}${SEED_USED:+, smallbank_seed=${SEED_USED}} <<-----------------"
echo "----------------->> Seed ${BENCHMARK} (reuse snapshot) <<-----------------"
bench_ensure_seed "${DB}" "${SEED_DB}"
# First rewrite smoke needs a live dataset; later candidates run on its dirt,
# which is fine (the smoke only checks for transaction errors).
bench_fresh_db "${DB}" "${SEED_DB}"

for candidate_id in "${CANDIDATE_IDS[@]}"; do
    echo "----------------->> [${BENCHMARK}] candidate ${candidate_id} <<-----------------"

    candidate_rel="${SCRATCH}/candidates/${candidate_id}"
    scores_dir="${ROOT}/${SCRATCH}/scores/${candidate_id}"
    rm -rf "${ROOT}/${candidate_rel}" "${scores_dir}"
    mkdir -p "${scores_dir}"

    export NAIVE_REWRITE_ROOT="${candidate_rel}"
    if [ "${candidate_id}" = "control" ]; then
        unset PROMPT_FILE
        prompt_field="control"
    else
        export PROMPT_FILE="${PROMPT_DIR}/${candidate_id}.txt"
        prompt_field="${PROMPT_FILE}"
    fi

    status="failed"
    score=""
    csv_path=""
    arm="search-${candidate_id}"

    if ! "${REWRITE_DRIVER}" "${SOURCE_PATH}" "${DBMS}" "${BENCHMARK}" "${SEARCH_MODEL}"; then
        echo "WARNING: rewrite/smoke failed for candidate '${candidate_id}'; skipping measurement." >&2
    elif bench_fresh_db "${DB}" "${SEED_DB}"; then
        rm -f "${scores_dir}/${arm}.csv" "${scores_dir}/${arm}"_r*.csv
        run_ok=1
        if [ "${BENCHMARK}" = "tpcc" ]; then
            PHASE=execute BENCH_RESULTS_DIR="${scores_dir}" "${RUNNER}" \
                "${DBMS}" "${TPCC_WAREHOUSES}" "${TPCC_CLIENTS}" "${BENCHMARK}" "${arm}" || run_ok=0
        else
            PHASE=execute BENCH_RESULTS_DIR="${scores_dir}" "${RUNNER}" \
                "${DBMS}" "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_TRANSACTIONS}" "${BENCHMARK}" "${arm}" || run_ok=0
        fi

        if [ "${run_ok}" -ne 1 ]; then
            echo "WARNING: workload failed for candidate '${candidate_id}'." >&2
        else
            CSVS=()
            if [ "${REPS}" -eq 1 ]; then
                candidate_csv="${scores_dir}/${arm}.csv"
                if [ -f "${candidate_csv}" ]; then
                    CSVS+=("${candidate_csv}")
                fi
            else
                for candidate_csv in "${scores_dir}/${arm}"_r*.csv; do
                    if [ -f "${candidate_csv}" ]; then
                        CSVS+=("${candidate_csv}")
                    fi
                done
            fi

            if [ "${#CSVS[@]}" -eq 0 ]; then
                echo "WARNING: no CSV produced for candidate '${candidate_id}'." >&2
            else
                VALS=()
                parse_ok=1
                for candidate_csv in "${CSVS[@]}"; do
                    if ! value="$(total_of "${candidate_csv}")"; then
                        parse_ok=0
                        break
                    fi
                    VALS+=("${value}")
                done
                if [ "${parse_ok}" -eq 1 ] && [ "${#VALS[@]}" -gt 0 ]; then
                    score="$(median_of "${VALS[@]}")"
                    status="ok"
                    csv_path="$(IFS=,; echo "${CSVS[*]}")"
                fi
            fi
        fi
    else
        echo "WARNING: fresh DB restore failed for candidate '${candidate_id}'." >&2
    fi

    rewritten_root="${ROOT}/${candidate_rel}/Rewrite/${DBMS}/${BENCHMARK}-NaiveLLM"
    sha="$(combined_sha256 "${rewritten_root}/drivers/postgresdriver.py" "${rewritten_root}/${ENTRY_FILE}")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${candidate_id}" "${status}" "${score}" "${csv_path}" "${prompt_field}" "${sha}" \
        >> "${SCORES_TSV}"

    echo "----------------->> [${BENCHMARK}] candidate ${candidate_id}: ${status}${score:+ (${score} txn/s)} <<-----------------"
done

SEARCH_JSON="${ROOT}/${SCRATCH}/search-${BENCHMARK}.json"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if ! winner_line="$(python3 - "${SCORES_TSV}" "${SEARCH_JSON}" "${BENCHMARK}" "${DBMS}" \
    "${SEARCH_MODEL}" "${REPS}" "${SEED_USED}" "${TIMESTAMP}" <<'PY'
import json
import sys

tsv_path, json_path, benchmark, dbms, model, reps, seed, timestamp = sys.argv[1:9]
candidates = []
with open(tsv_path, encoding="utf-8") as handle:
    for line in handle:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        while len(parts) < 6:
            parts.append("")
        cid, status, score, csv_path, prompt, sha = parts[:6]
        candidates.append({
            "id": cid,
            "status": status,
            "score": float(score) if score else None,
            "csv": csv_path or None,
            "prompt": prompt or None,
            "sha256": sha or None,
        })

document = {
    "benchmark": benchmark,
    "dbms": dbms,
    "model": model,
    "reps": int(reps),
    "smallbank_seed": int(seed) if seed else None,
    "timestamp": timestamp,
    "candidates": candidates,
}
with open(json_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")

scored = [c for c in candidates if c["status"] == "ok" and c["score"] is not None]
if not scored:
    sys.exit(3)
# Highest median TOTAL rate wins; exact ties go to the smallest id.
scored.sort(key=lambda c: (-c["score"], c["id"]))
print("{}\t{}".format(scored[0]["id"], scored[0]["score"]))
PY
)"; then
    echo "ERROR: no candidate produced a successful score (see ${SCRATCH}/search-${BENCHMARK}.json)." >&2
    exit 1
fi

winner="${winner_line%%$'\t'*}"
winner_score="${winner_line#*$'\t'}"

SELECTED="${ROOT}/${SCRATCH}/selected-${BENCHMARK}.txt"
if [ "${winner}" = "control" ]; then
    : > "${SELECTED}"
else
    cp "${PROMPT_DIR}/${winner}.txt" "${SELECTED}"
fi

echo
echo "----------------->> Scores (${BENCHMARK}, median TOTAL txn/s) <<-----------------"
printf '%-32s %-8s %12s\n' "candidate" "status" "txn/s"
awk -F'\t' '{ score = $3; if (score == "") score = "-"; printf "%-32s %-8s %12s\n", $1, $2, score }' "${SCORES_TSV}"

echo
echo "Winner: ${winner} (${winner_score} txn/s)"
echo "JSON:   ${SCRATCH}/search-${BENCHMARK}.json"
echo "Prompt: ${SCRATCH}/selected-${BENCHMARK}.txt"
echo "Promote with:"
echo "  cp \"${SCRATCH}/selected-${BENCHMARK}.txt\" \"${ROOT}/baselines/NaiveLLM/prompts/selected-${BENCHMARK}.txt\""
