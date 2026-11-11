#!/usr/bin/env bash
# Prompt repair loop for the Naive-LLM app-layer baseline.
#
# Usage: run_prompt_search.sh <benchmark: tpcc> [dbms=postgres] [model]
#
# One mutable prompt, seeded from prompts/basis.txt:
#   rewrite -> four correctness gates -> PASS twice => freeze; otherwise the
#   failing gates plus the offending diff are fed back and the prompt is
#   revised by a model. The frozen prompts/selected.txt is generated, never
#   hand-edited.
#
# Env: MAX_ITERS (8), CONFIRM_TEMPERATURE (0.2), VERIFY_SEED_DB
#      (tpcc_verify_seed), VERIFY_WAREHOUSES (1), VERIFY_DURATION (10),
#      VERIFY_TIMEOUT (300), RESEED (0), SMOKE_SECS (10).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/scripts/_lib/bench_lib.sh"

BENCHMARK="${1:-}"
DBMS="${2:-postgres}"
SEARCH_MODEL="${3:-${MODEL:-gemini-3.5-flash-lite}}"
IMPROVER_MODEL="${IMPROVER_MODEL:-${SEARCH_MODEL}}"
MAX_ITERS="${MAX_ITERS:-8}"
CONFIRM_TEMPERATURE="${CONFIRM_TEMPERATURE:-0.2}"
CONFIRM_TRIES="${CONFIRM_TRIES:-3}"
VERIFY_SEED_DB="${VERIFY_SEED_DB:-tpcc_verify_seed}"
VERIFY_WAREHOUSES="${VERIFY_WAREHOUSES:-1}"
VERIFY_DURATION="${VERIFY_DURATION:-10}"
SMOKE_SECS="${SMOKE_SECS:-10}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-300}"

# The search must never touch the performance seed (tpcc_seed) or its scale.
# It runs exclusively on the small verify seed and the working 'tpcc' DB
# restored from it.
if [ "${VERIFY_SEED_DB}" = "tpcc_seed" ]; then
    echo "ERROR: the prompt search must use the verify seed (e.g. tpcc_verify_seed), not the performance seed 'tpcc_seed'." >&2
    exit 2
fi

PROMPT_DIR="${ROOT}/baselines/NaiveLLM/prompts"
BASIS_FILE="${PROMPT_DIR}/basis.txt"
SELECTED_FILE="${PROMPT_DIR}/selected.txt"
META_FILE="${PROMPT_DIR}/selected.meta.json"
IMPROVER="${ROOT}/scripts/common/app_layer/exp3_PromptSearch/improve_prompt.py"
REWRITE_DRIVER="${ROOT}/scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh"
VERIFIER="${ROOT}/scripts/tpcc/exp2_Correctness/run_verify.sh"

if [ "${BENCHMARK}" != "tpcc" ]; then
    echo "Usage: $(basename "$0") <benchmark: tpcc> [dbms=postgres] [model]" >&2
    echo "Only tpcc has a correctness oracle; Smallbank is deferred." >&2
    exit 2
fi
if ! [[ "${MAX_ITERS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: MAX_ITERS must be a positive integer (got '${MAX_ITERS}')." >&2
    exit 2
fi
if ! [[ "${CONFIRM_TRIES}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: CONFIRM_TRIES must be a positive integer (got '${CONFIRM_TRIES}')." >&2
    exit 2
fi
for path in "${BASIS_FILE}" "${IMPROVER}" "${REWRITE_DRIVER}" "${VERIFIER}"; do
    if [ ! -f "${path}" ]; then
        echo "ERROR: missing ${path}" >&2
        exit 1
    fi
done
if [ ! -x "${ROOT}/baselines/NaiveLLM/venv/bin/python" ]; then
    echo "ERROR: NaiveLLM venv missing; run ./run/setup/app-setup-baselines.sh" >&2
    exit 1
fi
if [ ! -x "${ROOT}/workload/apps/tpcc/venv/bin/python" ]; then
    echo "ERROR: TPC-C workload venv missing; run ./run/setup/app-setup-workloads.sh" >&2
    exit 1
fi
if ! grep -q "VERIFY_SKIP_SEED_ASSERT" "${ROOT}/scripts/_lib/bench_lib.sh"; then
    echo "ERROR: scripts/_lib/bench_lib.sh is outdated (missing VERIFY_SKIP_SEED_ASSERT)." >&2
    echo "Sync the repo before running the prompt loop." >&2
    exit 1
fi

bench_lock "${ROOT}"
export BENCH_LOCK_HELD=1
export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"
# Rewrites and their smoke runs use the small verify seed, never the full one.
export SMOKE_SECS SMOKE_CLIENTS=1 TPCC_WAREHOUSES="${VERIFY_WAREHOUSES}"

# --- verify seed (created once) --------------------------------------------
echo "----------------->> Seed ${VERIFY_SEED_DB} (${VERIFY_WAREHOUSES} warehouses) <<-----------------"
_seed_exists="$(psql -d postgres -tA -c "SELECT 1 FROM pg_database WHERE datname='${VERIFY_SEED_DB}'" 2>/dev/null || true)"
if [ "${RESEED:-0}" = "1" ] || [[ "${_seed_exists}" != *1* ]]; then
    bench_seed_once tpcc "${VERIFY_SEED_DB}"
else
    echo "Reusing existing seed database '${VERIFY_SEED_DB}'."
fi
bench_assert_rows "${VERIFY_SEED_DB}" warehouse "${VERIFY_WAREHOUSES}"
unset _seed_exists
bench_fresh_db tpcc "${VERIFY_SEED_DB}"

# --- scratch ---------------------------------------------------------------
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
SCRATCH="out/app_layer/NaiveLLM-search-results/${STAMP}"
mkdir -p "${ROOT}/${SCRATCH}"
HISTORY="${SCRATCH}/history.tsv"
printf 'iteration\tphase\trewrite\tgates\tprompt_sha256\trewrite_sha256\n' > "${ROOT}/${HISTORY}"
WORK_PROMPT="${SCRATCH}/prompt-iter-00.txt"
cp "${BASIS_FILE}" "${ROOT}/${WORK_PROMPT}"

# Schema table names plus workload terms must never appear in the guidance;
# the frozen prompt has to generalize to any codebase.
DENY_TOKENS="${DENY_TOKENS:-tpcc,smallbank,neworder,new_order,order_line,orderstatus,stocklevel,warehouse,district,customer,orders,item,stock,history,payment,delivery}"
SCHEMA_FILE="${ROOT}/workload/apps/tpcc/tpcc.postgres.sql"
if [ -f "${SCHEMA_FILE}" ]; then
    schema_tokens="$(grep -oiE 'CREATE[[:space:]]+TABLE([[:space:]]+IF[[:space:]]+NOT[[:space:]]+EXISTS)?[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "${SCHEMA_FILE}" \
        | awk '{print $NF}' | paste -sd, - || true)"
    [ -n "${schema_tokens}" ] && DENY_TOKENS="${DENY_TOKENS},${schema_tokens}"
fi

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

json_status() {
    python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        document = json.load(handle)
except (OSError, ValueError):
    print("UNVERIFIED")
    raise SystemExit
print(str(document.get("status") or "UNVERIFIED").upper())
PY
}

build_feedback() {
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, os, sys
out, rewrite_status, rewrite_log, verify_json, smoke_log = sys.argv[1:6]
verify = None
if verify_json and os.path.exists(verify_json):
    try:
        with open(verify_json, encoding="utf-8") as handle:
            verify = json.load(handle)
    except (OSError, ValueError):
        verify = None
tail = ""
if rewrite_log and os.path.exists(rewrite_log):
    with open(rewrite_log, encoding="utf-8", errors="replace") as handle:
        tail = handle.read()[-2000:]
smoke_errors = []
if smoke_log and os.path.exists(smoke_log):
    seen = set()
    with open(smoke_log, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if "WARNING:" not in line and "ERROR" not in line and "Traceback" not in line:
                continue
            message = line.strip()
            if message in seen:
                continue
            seen.add(message)
            smoke_errors.append(message)
            if len(smoke_errors) >= 15:
                break
with open(out, "w", encoding="utf-8") as handle:
    json.dump({"rewrite_status": rewrite_status,
               "rewrite_log_tail": tail,
               "smoke_errors": smoke_errors,
               "verify": verify}, handle, indent=2)
    handle.write("\n")
PY
}

write_diff() {
    local out="$1" tree_rel="$2" rel orig new
    : > "${out}"
    for rel in drivers/postgresdriver.py tpcc.py; do
        orig="${ROOT}/workload/apps/tpcc/${rel}"
        new="${ROOT}/${tree_rel}/${rel}"
        if [ -f "${orig}" ] && [ -f "${new}" ]; then
            diff -u "${orig}" "${new}" >> "${out}" || true
        fi
    done
    head -c 8000 "${out}" > "${out}.cut" && mv "${out}.cut" "${out}"
}

run_rewrite() {
    local prompt="$1" dir_rel="$2" log="$3" temperature="${4:-}" rc=0
    TEMPERATURE="${temperature}" NAIVE_REWRITE_ROOT="${dir_rel}" PROMPT_FILE="${prompt}" \
        bash "${REWRITE_DRIVER}" workload/apps/tpcc "${DBMS}" tpcc "${SEARCH_MODEL}" \
        >"${log}" 2>&1 || rc=$?
    return "${rc}"
}

verify_tree() {
    local arm="$1" dir_rel="$2"
    mkdir -p "${ROOT}/${dir_rel}/smoke/benchmarks"
    BENCH_LOCK_HELD=1 REVERIFY=1 \
        VERIFY_SKIP_SEED=1 VERIFY_SKIP_SEED_ASSERT=1 \
        VERIFY_SEED_DB="${VERIFY_SEED_DB}" \
        VERIFY_WAREHOUSES="${VERIFY_WAREHOUSES}" \
        VERIFY_DURATION="${VERIFY_DURATION}" \
        RESTORE_RESTART=0 BENCH_SKIP_SETTLE=1 \
        VERIFY_REWRITE_ROOT="${dir_rel}" \
        VERIFY_CSV="${ROOT}/${dir_rel}/smoke/${arm}.csv" \
        BENCH_RESULTS_DIR="${ROOT}/${dir_rel}/smoke/benchmarks" \
        VERIFY_OUTPUT="${ROOT}/${dir_rel}/verify.json" \
        timeout --kill-after=5 "${VERIFY_TIMEOUT}" \
        bash "${VERIFIER}" "${DBMS}" "${arm}" \
        >"${ROOT}/${dir_rel}/verify.log" 2>&1 || true
}

# One rewrite + verify attempt. Echoes "<rewrite>\t<gates>".
attempt() {
    local prompt="$1" dir_rel="$2" temperature="${3:-}"
    local tree_rel rw="ok" gates="UNVERIFIED"
    tree_rel="${dir_rel}/Rewrite/${DBMS}/tpcc-NaiveLLM"
    mkdir -p "${ROOT}/${dir_rel}"
    cp "${prompt}" "${ROOT}/${dir_rel}/prompt.txt"
    if ! run_rewrite "${ROOT}/${dir_rel}/prompt.txt" "${dir_rel}" "${ROOT}/${dir_rel}/rewrite.log" "${temperature}"; then
        rw="failed"
    fi
    if [ "${rw}" = "ok" ] && [ ! -f "${ROOT}/${tree_rel}/drivers/postgresdriver.py" ]; then
        rw="missing"
    fi
    if [ "${rw}" = "ok" ]; then
        verify_tree "prompt-repair-${dir_rel##*/}" "${dir_rel}"
        gates="$(json_status "${ROOT}/${dir_rel}/verify.json")"
    fi
    printf '%s\t%s\n' "${rw}" "${gates}"
}

echo "----------------->> Prompt repair: ${BENCHMARK} (${DBMS}), model=${SEARCH_MODEL}, improver=${IMPROVER_MODEL}, seed=${VERIFY_SEED_DB}, max_iterations=${MAX_ITERS} <<-----------------"
echo "Seed prompt: ${BASIS_FILE}"

seen=""
frozen=0
final_iter=""

for ((i = 1; i <= MAX_ITERS; i++)); do
    idx="$(printf '%02d' "${i}")"
    prompt_sha="$(sha256_file "${ROOT}/${WORK_PROMPT}")"

    case " ${seen} " in
        *" ${prompt_sha} "*)
            echo "ERROR: revised prompt repeats an earlier one (sha ${prompt_sha}); the improver is stalled." >&2
            echo "Scratch: ${SCRATCH}" >&2
            exit 3
            ;;
    esac
    seen="${seen} ${prompt_sha}"

    iter_rel="${SCRATCH}/iter-${idx}"
    IFS=$'\t' read -r rw_status gate_status < <(attempt "${ROOT}/${WORK_PROMPT}" "${iter_rel}" "")
    echo "iteration ${i}/${MAX_ITERS}: rewrite=${rw_status} gates=${gate_status}"
    tree_rel="${iter_rel}/Rewrite/${DBMS}/tpcc-NaiveLLM"
    rewrite_sha=""
    if [ -f "${ROOT}/${tree_rel}/drivers/postgresdriver.py" ]; then
        rewrite_sha="$(cat "${ROOT}/${tree_rel}/drivers/postgresdriver.py" "${ROOT}/${tree_rel}/tpcc.py" 2>/dev/null \
            | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | awk '{print $1}')"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${i}" "rewrite" "${rw_status}" "${gate_status}" "${prompt_sha}" "${rewrite_sha}" >> "${ROOT}/${HISTORY}"

    if [ "${gate_status}" = "PASS" ]; then
        # Resample the same prompt before touching it: rewriting is not
        # deterministic even at temperature 0, so one bad resample must not
        # discard a prompt that already passed.
        for ((t = 1; t <= CONFIRM_TRIES; t++)); do
            confirm_rel="${iter_rel}-confirm-${t}"
            IFS=$'\t' read -r confirm_rw confirm_gates < <(attempt "${ROOT}/${WORK_PROMPT}" "${confirm_rel}" "${CONFIRM_TEMPERATURE}")
            echo "iteration ${i}: confirmation ${t}/${CONFIRM_TRIES} (temperature ${CONFIRM_TEMPERATURE}): rewrite=${confirm_rw} gates=${confirm_gates}"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${i}" "confirm-${t}" "${confirm_rw}" "${confirm_gates}" "${prompt_sha}" "" >> "${ROOT}/${HISTORY}"
            if [ "${confirm_gates}" = "PASS" ]; then
                frozen=1
                final_iter="${i}"
                break 2
            fi
            iter_rel="${confirm_rel}"
            rw_status="${confirm_rw}"
            gate_status="${confirm_gates}"
        done
    fi

    echo "----------------->> iteration ${i}: repairing prompt <<-----------------"
    build_feedback "${ROOT}/${iter_rel}/feedback.json" "${rw_status}" \
        "${ROOT}/${iter_rel}/rewrite.log" "${ROOT}/${iter_rel}/verify.json" \
        "${ROOT}/${iter_rel}/Rewrite/${DBMS}/smoke.log"
    write_diff "${ROOT}/${iter_rel}/diff.txt" "${iter_rel}/Rewrite/${DBMS}/tpcc-NaiveLLM"
    next_prompt="${SCRATCH}/prompt-iter-$(printf '%02d' $((i + 1))).txt"
    if ! "${ROOT}/baselines/NaiveLLM/venv/bin/python" "${IMPROVER}" \
        --current "${ROOT}/${WORK_PROMPT}" \
        --output "${ROOT}/${next_prompt}" \
        --feedback "${ROOT}/${iter_rel}/feedback.json" \
        --diff "${ROOT}/${iter_rel}/diff.txt" \
        --deny "${DENY_TOKENS}" \
        --model "${IMPROVER_MODEL}" \
        --meta "${ROOT}/${iter_rel}/prompt.meta.json"; then
        echo "ERROR: prompt repair failed at iteration ${i}. Scratch: ${SCRATCH}" >&2
        exit 1
    fi
    WORK_PROMPT="${next_prompt}"
done

if [ "${frozen}" -ne 1 ]; then
    echo "ERROR: no prompt passed twice within ${MAX_ITERS} iterations." >&2
    echo "Last prompt: ${WORK_PROMPT}" >&2
    echo "Scratch: ${SCRATCH}" >&2
    exit 3
fi

cp "${ROOT}/${WORK_PROMPT}" "${SELECTED_FILE}"
python3 - "${META_FILE}" "${SELECTED_FILE}" "${ROOT}/${HISTORY}" "${SEARCH_MODEL}" \
    "${IMPROVER_MODEL}" "${CONFIRM_TEMPERATURE}" "${VERIFY_SEED_DB}" "${VERIFY_WAREHOUSES}" \
    "${final_iter}" "${ROOT}/${SCRATCH}" <<'PY'
import glob, hashlib, json, os, sys
from datetime import datetime, timezone

meta_path, selected, history, model, improver_model, temperature, seed_db, warehouses, iterations, scratch = sys.argv[1:11]
with open(selected, "rb") as handle:
    prompt_bytes = handle.read()

rows = []
with open(history, encoding="utf-8") as handle:
    header = handle.readline().rstrip("\n").split("\t")
    for line in handle:
        row = line.rstrip("\n").split("\t")
        if len(row) == len(header):
            rows.append(dict(zip(header, row)))

repairs = []
for repair_path in sorted(glob.glob(os.path.join(scratch, "iter-*", "prompt.meta.json"))):
    try:
        with open(repair_path, encoding="utf-8") as handle:
            repairs.append(json.load(handle))
    except (OSError, ValueError):
        continue

document = {
    "generated": True,
    "status": "pass",
    "benchmark": "tpcc",
    "model": model,
    "improver_model": improver_model,
    "iterations": int(iterations),
    "confirm_temperature": float(temperature),
    "verify_seed_db": seed_db,
    "verify_warehouses": int(warehouses),
    "prompt_file": os.path.relpath(selected),
    "prompt_sha256": hashlib.sha256(prompt_bytes).hexdigest(),
    "prompt_bytes": len(prompt_bytes),
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "history": rows,
    "repairs": repairs,
}
with open(meta_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
print("frozen prompt: {} ({} bytes, sha {})".format(
    os.path.relpath(selected), len(prompt_bytes), document["prompt_sha256"]))
PY

echo
echo "Frozen:  ${SELECTED_FILE}"
echo "Meta:    ${META_FILE}"
echo "Scratch: ${SCRATCH}"
echo "Next:    ./run/tpcc/run_naive-llm.sh          # measure"
echo "         ./run/tpcc/run_naive-llm-robustness.sh  # re-verify the frozen prompt"
